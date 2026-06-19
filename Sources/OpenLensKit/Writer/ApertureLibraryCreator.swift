import Foundation

/// Creates a new, empty Aperture-style library package that OpenLens can open.
///
/// This authors the parts OpenLens reads: the package folders, `Info.plist`,
/// `Aperture.aplib/DataModelVersion.plist`, and a `Library.apdb` SQLite catalog
/// with the `RK*` tables plus Aperture's standard system folders and smart
/// albums. It is sufficient for OpenLens; full byte-for-byte compatibility with
/// Aperture itself (every one of its ~33 tables and admin records) is a later
/// refinement — most users will open their existing libraries instead.
public struct ApertureLibraryCreator {

    public enum CreateError: Error, CustomStringConvertible {
        case alreadyExists(String)
        public var description: String {
            switch self {
            case .alreadyExists(let p): return "A file already exists at \(p)"
            }
        }
    }

    /// Creates a new library at `url` (which should end in `.aplibrary`) and
    /// returns an opened `ApertureLibrary` for it. Optionally seeds a first
    /// project.
    @discardableResult
    public static func createLibrary(at url: URL,
                                     firstProjectNamed projectName: String? = nil) throws -> ApertureLibrary {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else {
            throw CreateError.alreadyExists(url.path)
        }

        // Package folders.
        for sub in ["Database/apdb", "Database/Versions", "Masters", "Previews",
                    "Thumbnails", "Aperture.aplib"] {
            try fm.createDirectory(at: url.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }

        // Info.plist
        let info: [String: Any] = [
            "CFBundleShortVersionString": "3.6",
            "CFBundleIdentifier": "com.apple.Aperture.library",
            "CFBundleName": "Aperture Library",
            "CFBundleGetInfoString": "Aperture Library 3.6"
        ]
        try writePlist(info, to: url.appendingPathComponent("Info.plist"))
        try writePlist(["DataModelVersion": "110"],
                       to: url.appendingPathComponent("Aperture.aplib/DataModelVersion.plist"))

        // Catalog
        let dbPath = url.appendingPathComponent("Database/apdb/Library.apdb").path
        let db = try SQLiteDatabase(path: dbPath, readOnly: false, create: true)
        try createSchema(db)
        try seedSystemRows(db, projectName: projectName)

        return try ApertureLibrary(url: url)
    }

    // MARK: - Schema

    private static func createSchema(_ db: SQLiteDatabase) throws {
        let statements = [
            """
            CREATE TABLE RKFolder(modelId INTEGER PRIMARY KEY, uuid varchar, folderType INTEGER,
              name varchar, parentFolderUuid varchar, implicitAlbumUuid varchar,
              posterVersionUuid varchar, versionCount INTEGER, folderPath varchar,
              createDate timestamp, isInTrash INTEGER, isHidden INTEGER, colorLabelIndex INTEGER)
            """,
            """
            CREATE TABLE RKMaster(modelId INTEGER PRIMARY KEY, uuid varchar, name varchar,
              projectUuid varchar, importGroupUuid varchar, fileName varchar, originalFileName varchar,
              type varchar, subtype varchar, fileIsReference INTEGER, isMissing INTEGER,
              imagePath varchar, fileSize INTEGER, imageDate timestamp, createDate timestamp, isInTrash INTEGER)
            """,
            """
            CREATE TABLE RKVersion(modelId INTEGER PRIMARY KEY, uuid varchar, name varchar,
              fileName varchar, versionNumber INTEGER, stackUuid varchar, masterUuid varchar,
              projectUuid varchar, imageDate timestamp, mainRating INTEGER, isHidden INTEGER,
              isFlagged INTEGER, isOriginal INTEGER, isEditable INTEGER, colorLabelIndex INTEGER,
              masterWidth INTEGER, masterHeight INTEGER, processedWidth INTEGER, processedHeight INTEGER,
              rotation INTEGER, hasAdjustments INTEGER, hasKeywords INTEGER, createDate timestamp,
              isInTrash INTEGER, showInLibrary INTEGER, exifLatitude REAL, exifLongitude REAL)
            """,
            """
            CREATE TABLE RKAlbum(modelId INTEGER PRIMARY KEY, uuid varchar, name varchar,
              albumType INTEGER, albumSubclass INTEGER, folderUuid varchar, isMagic INTEGER, isInTrash INTEGER)
            """,
            "CREATE TABLE RKAlbumVersion(modelId INTEGER PRIMARY KEY, versionId INTEGER, albumId INTEGER)",
            """
            CREATE TABLE RKKeyword(modelId INTEGER PRIMARY KEY, uuid varchar, name varchar,
              searchName varchar, parentId INTEGER, hasChildren INTEGER, shortcut varchar)
            """,
            "CREATE TABLE RKKeywordForVersion(modelId INTEGER PRIMARY KEY, versionId INTEGER, keywordId INTEGER)",
            """
            CREATE TABLE RKStackState(modelId INTEGER PRIMARY KEY, stackUuid varchar, albumUuid varchar,
              albumPick varchar, isExpanded INTEGER)
            """,
            "CREATE TABLE RKStackContent(modelId INTEGER PRIMARY KEY, stackUuid varchar, versionUuid varchar, orderNumber INTEGER)",
            """
            CREATE TABLE RKImageAdjustment(modelId INTEGER PRIMARY KEY, uuid varchar, name varchar,
              versionUuid varchar, maskUuid varchar, adjIndex INTEGER, isEnabled INTEGER, data BLOB, dbVersion INTEGER)
            """
        ]
        for sql in statements { try db.execute(sql) }
    }

    private static func seedSystemRows(_ db: SQLiteDatabase, projectName: String?) throws {
        let now = Date().timeIntervalSinceReferenceDate
        func folder(_ id: Int, _ uuid: String, _ type: Int, _ name: String,
                    _ parent: String?, _ path: String) throws {
            try db.execute("""
                INSERT INTO RKFolder(modelId, uuid, folderType, name, parentFolderUuid,
                    versionCount, folderPath, createDate, isInTrash, isHidden, colorLabelIndex)
                VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0, 0, -1)
                """, [.integer(Int64(id)), .text(uuid), .integer(Int64(type)), .text(name),
                      parent.map { .text($0) } ?? .null, .text(path), .real(now)])
        }
        try folder(1, "LibraryFolder", 1, "", nil, "1/")
        try folder(2, "AllProjectsItem", 1, "Projects", "LibraryFolder", "1/2/")
        try folder(3, "TrashFolder", 1, "Trash", "LibraryFolder", "1/3/")

        // Standard smart albums (so Library sources / classification line up).
        func album(_ id: Int, _ uuid: String, _ name: String, _ subclass: Int,
                   _ folder: String, _ magic: Int) throws {
            try db.execute("""
                INSERT INTO RKAlbum(modelId, uuid, name, albumType, albumSubclass,
                    folderUuid, isMagic, isInTrash)
                VALUES (?, ?, ?, 1, ?, ?, ?, 0)
                """, [.integer(Int64(id)), .text(uuid), .text(name), .integer(Int64(subclass)),
                      .text(folder), .integer(Int64(magic))])
        }
        try album(1, "allPhotosAlbum", "allPhotosAlbum", 2, "LibraryFolder", 1)
        try album(2, "flaggedAlbum", "flaggedAlbum", 2, "LibraryFolder", 1)
        try album(3, "rejectedAlbum", "rejectedAlbum", 2, "LibraryFolder", 1)
        try album(4, "trashAlbum", "trashAlbum", 2, "TrashFolder", 1)

        if let projectName {
            try folder(10, UUID().uuidString, 2, projectName, "AllProjectsItem", "1/2/10/")
        }
    }

    private static func writePlist(_ dict: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
    }
}
