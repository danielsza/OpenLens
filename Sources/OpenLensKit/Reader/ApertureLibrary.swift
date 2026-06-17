import Foundation

/// Represents an Aperture library package (`*.aplibrary`) on disk and provides
/// read access to its contents.
///
/// Layout of an Aperture library (verified against a 3.6 library):
///
///   Library.aplibrary/
///     Info.plist                      bundle metadata (CFBundleShortVersionString = "3.6")
///     Database/
///       apdb/
///         Library.apdb                main catalog (SQLite): RKFolder, RKMaster, RKVersion, ...
///         Properties.apdb             EXIF/IPTC searchable properties
///         ImageProxies.apdb           thumbnail/preview bookkeeping
///         History.apdb, Faces.db, ...
///       Versions/<Y>/<M>/<D>/<import>/<masterUuid>/
///         Master.apmaster             per-master plist (mirror of RKMaster)
///         Version-0.apversion         original version plist (metadata, EXIF, IPTC)
///         Version-1.apversion         current editable version (+ imageProxyState)
///     Masters/<Y>/<M>/<D>/<import>/<file>   the original image files
///     Previews/  Thumbnails/                rendered JPEGs
///
/// NOTE: ratings/flags/labels are stored in BOTH the SQLite catalog
/// (`RKVersion`) and the per-version `.apversion` plist. Any writer must keep
/// the two in sync — see `ApertureLibraryWriter`.
public final class ApertureLibrary {

    public enum LibraryError: Error, CustomStringConvertible {
        case notADirectory(String)
        case missingDatabase(String)
        case unsupportedVersion(String)

        public var description: String {
            switch self {
            case .notADirectory(let p): return "Not an Aperture library directory: \(p)"
            case .missingDatabase(let p): return "Library catalog not found at: \(p)"
            case .unsupportedVersion(let v): return "Unsupported library version: \(v)"
            }
        }
    }

    public let url: URL
    public let version: String

    let libraryDB: SQLiteDatabase

    public var databaseURL: URL {
        url.appendingPathComponent("Database/apdb/Library.apdb")
    }
    public var mastersURL: URL { url.appendingPathComponent("Masters") }
    public var versionsURL: URL { url.appendingPathComponent("Database/Versions") }
    public var previewsURL: URL { url.appendingPathComponent("Previews") }
    public var thumbnailsURL: URL { url.appendingPathComponent("Thumbnails") }

    /// Opens a library for reading. Throws if the package is malformed.
    public init(url: URL) throws {
        self.url = url
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryError.notADirectory(url.path)
        }

        // Read and sanity-check Info.plist.
        let infoURL = url.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: infoURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let v = plist["CFBundleShortVersionString"] as? String {
            self.version = v
        } else {
            self.version = "unknown"
        }

        let dbPath = url.appendingPathComponent("Database/apdb/Library.apdb").path
        guard fm.fileExists(atPath: dbPath) else {
            throw LibraryError.missingDatabase(dbPath)
        }
        self.libraryDB = try SQLiteDatabase(path: dbPath, readOnly: true)
    }

    // MARK: - Projects / folders

    /// All folders and projects, ordered by their position in the tree.
    public func folders() throws -> [Project] {
        let rows = try libraryDB.query("""
            SELECT modelId, uuid, name, folderType, folderPath,
                   parentFolderUuid, versionCount, createDate
            FROM RKFolder
            WHERE isInTrash = 0 OR isInTrash IS NULL
            ORDER BY folderPath
            """)
        return rows.map { row in
            Project(
                id: row["uuid"]?.stringValue ?? "",
                modelId: row["modelId"]?.intValue ?? 0,
                name: row["name"]?.stringValue ?? "",
                folderType: row["folderType"]?.intValue ?? 0,
                folderPath: row["folderPath"]?.stringValue ?? "",
                parentUuid: row["parentFolderUuid"]?.stringValue,
                versionCount: row["versionCount"]?.intValue ?? 0,
                createDate: Self.appleDate(row["createDate"]?.doubleValue)
            )
        }
    }

    /// Just the user-visible projects (folderType == 2).
    public func projects() throws -> [Project] {
        try folders().filter { $0.isProject }
    }

    // MARK: - Versions

    /// All library versions (the browsable photos), optionally filtered to a
    /// single project. By default only "live" versions are returned
    /// (showInLibrary == 1), which excludes the hidden Version-0 originals.
    public func versions(inProject projectUuid: String? = nil,
                         includeHidden: Bool = false) throws -> [PhotoVersion] {
        var sql = """
            SELECT modelId, uuid, name, fileName, versionNumber, masterUuid,
                   projectUuid, mainRating, isFlagged, colorLabelIndex,
                   hasAdjustments, isOriginal, rotation, isInTrash,
                   showInLibrary, imageDate, masterWidth, masterHeight, stackUuid,
                   hasKeywords
            FROM RKVersion
            WHERE (isInTrash = 0 OR isInTrash IS NULL)
            """
        var params: [SQLiteDatabase.Value] = []
        if !includeHidden {
            sql += " AND showInLibrary = 1"
        }
        if let p = projectUuid {
            sql += " AND projectUuid = ?"
            params.append(.text(p))
        }
        sql += " ORDER BY imageDate, fileName"

        let rows = try libraryDB.query(sql, params)
        return rows.map { Self.makeVersion(from: $0) }
    }

    /// All masters, keyed by uuid (for joining to versions).
    public func mastersByUuid() throws -> [String: PhotoMaster] {
        let rows = try libraryDB.query("""
            SELECT modelId, uuid, fileName, originalFileName, imagePath,
                   projectUuid, type, fileIsReference, isMissing, fileSize
            FROM RKMaster
            """)
        var result: [String: PhotoMaster] = [:]
        for row in rows {
            let m = PhotoMaster(
                id: row["uuid"]?.stringValue ?? "",
                modelId: row["modelId"]?.intValue ?? 0,
                fileName: row["fileName"]?.stringValue ?? "",
                originalFileName: row["originalFileName"]?.stringValue,
                imagePath: row["imagePath"]?.stringValue ?? "",
                projectUuid: row["projectUuid"]?.stringValue ?? "",
                type: row["type"]?.stringValue ?? "",
                isReference: (row["fileIsReference"]?.intValue ?? 0) == 1,
                isMissing: (row["isMissing"]?.intValue ?? 0) == 1,
                fileSize: row["fileSize"]?.intValue
            )
            result[m.id] = m
        }
        return result
    }

    /// Convenience: versions joined to their masters as `Photo` records.
    public func photos(inProject projectUuid: String? = nil) throws -> [Photo] {
        let masters = try mastersByUuid()
        let versions = try versions(inProject: projectUuid)
        return versions.compactMap { v in
            guard let m = masters[v.masterUuid] else { return nil }
            return Photo(version: v, master: m)
        }
    }

    /// Absolute URL of the original file backing a master (when stored inside
    /// the library; referenced masters are resolved elsewhere via aliases).
    public func masterFileURL(for master: PhotoMaster) -> URL {
        mastersURL.appendingPathComponent(master.imagePath)
    }

    // MARK: - Helpers

    static func makeVersion(from row: SQLiteDatabase.Row) -> PhotoVersion {
        PhotoVersion(
            id: row["uuid"]?.stringValue ?? "",
            modelId: row["modelId"]?.intValue ?? 0,
            name: row["name"]?.stringValue ?? "",
            fileName: row["fileName"]?.stringValue ?? "",
            versionNumber: row["versionNumber"]?.intValue ?? 0,
            masterUuid: row["masterUuid"]?.stringValue ?? "",
            projectUuid: row["projectUuid"]?.stringValue ?? "",
            rating: row["mainRating"]?.intValue ?? 0,
            isFlagged: (row["isFlagged"]?.intValue ?? 0) == 1,
            colorLabel: row["colorLabelIndex"]?.intValue ?? -1,
            hasAdjustments: (row["hasAdjustments"]?.intValue ?? 0) == 1,
            isOriginal: (row["isOriginal"]?.intValue ?? 0) == 1,
            rotation: row["rotation"]?.intValue ?? 0,
            isInTrash: (row["isInTrash"]?.intValue ?? 0) == 1,
            showInLibrary: (row["showInLibrary"]?.intValue ?? 0) == 1,
            imageDate: appleDate(row["imageDate"]?.doubleValue),
            masterWidth: row["masterWidth"]?.intValue,
            masterHeight: row["masterHeight"]?.intValue,
            stackUuid: row["stackUuid"]?.stringValue,
            hasKeywords: (row["hasKeywords"]?.intValue ?? 0) == 1
        )
    }

    /// Aperture/Core Data store timestamps as seconds since the reference date
    /// 2001-01-01 (NSDate epoch), not the Unix epoch.
    static func appleDate(_ value: Double?) -> Date? {
        guard let v = value else { return nil }
        return Date(timeIntervalSinceReferenceDate: v)
    }
}
