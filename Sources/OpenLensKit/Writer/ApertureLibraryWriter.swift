import Foundation

/// Performs the small set of *safe* mutations OpenLens supports today:
/// ratings, flags, and colour labels.
///
/// IMPORTANT — data integrity:
/// Aperture stores these attributes in two places that must agree:
///   1. The `RKVersion` row in `Database/apdb/Library.apdb`.
///   2. The matching `Version-N.apversion` property list under
///      `Database/Versions/.../<masterUuid>/`.
/// We update both inside one logical operation. We do NOT yet rewrite the
/// `Properties.apdb` search index or append a `History` entry — those affect
/// search and undo, not correctness of the rating itself, and are tracked on
/// the roadmap.
///
/// SAFETY: this class refuses to run unless you opt in via `allowWrites`,
/// and it always writes to the catalog with SQLite read-write mode. Always
/// operate on a COPY of a library until the writer is fully validated.
public final class ApertureLibraryWriter {

    public enum WriteError: Error, CustomStringConvertible {
        case writesNotAllowed
        case versionNotFound(String)
        case plistNotFound(String)

        public var description: String {
            switch self {
            case .writesNotAllowed:
                return "Writes are disabled. Initialise with allowWrites: true (and back up your library first)."
            case .versionNotFound(let u): return "No RKVersion with uuid \(u)"
            case .plistNotFound(let u): return "No .apversion plist found for version \(u)"
            }
        }
    }

    private let libraryURL: URL
    private let allowWrites: Bool

    public init(libraryURL: URL, allowWrites: Bool = false) {
        self.libraryURL = libraryURL
        self.allowWrites = allowWrites
    }

    private var dbPath: String {
        libraryURL.appendingPathComponent("Database/apdb/Library.apdb").path
    }

    /// Makes a timestamped copy of the catalog before mutating it. Call once
    /// before a batch of edits. Returns the backup URL.
    @discardableResult
    public func backupCatalog() throws -> URL {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = libraryURL.appendingPathComponent("OpenLensBackups", isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let dst = backupDir.appendingPathComponent("Library-\(stamp).apdb")
        try fm.copyItem(at: URL(fileURLWithPath: dbPath), to: dst)
        return dst
    }

    // MARK: - Public API

    /// Sets the star rating (0...5) for a version.
    public func setRating(_ rating: Int, forVersion uuid: String) throws {
        try updateVersion(uuid: uuid,
                          columns: ["mainRating": .integer(Int64(clampRating(rating)))],
                          plistKeys: ["mainRating": clampRating(rating)],
                          iptcStarRating: clampRating(rating))
    }

    /// Flags / unflags a version.
    public func setFlagged(_ flagged: Bool, forVersion uuid: String) throws {
        try updateVersion(uuid: uuid,
                          columns: ["isFlagged": .integer(flagged ? 1 : 0)],
                          plistKeys: ["isFlagged": flagged],
                          iptcStarRating: nil)
    }

    /// Sets the colour label (-1 == none, 0...6).
    public func setColorLabel(_ label: Int, forVersion uuid: String) throws {
        try updateVersion(uuid: uuid,
                          columns: ["colorLabelIndex": .integer(Int64(label))],
                          plistKeys: ["colorLabelIndex": label],
                          iptcStarRating: nil)
    }

    // MARK: - Rotation

    /// Sets absolute rotation (degrees clockwise) on a version.
    public func setRotation(_ degrees: Int, forVersion uuid: String) throws {
        let d = ((degrees % 360) + 360) % 360
        try updateVersion(uuid: uuid,
                          columns: ["rotation": .integer(Int64(d))],
                          plistKeys: ["rotation": d],
                          iptcStarRating: nil)
    }

    /// Rotates a version 90° left or right relative to its current rotation.
    public func rotate(_ uuid: String, clockwise: Bool, currentRotation: Int) throws {
        try setRotation(currentRotation + (clockwise ? 90 : -90), forVersion: uuid)
    }

    // MARK: - IPTC metadata

    /// Edits IPTC fields on a version's `.apversion` plist. Only the provided
    /// (non-nil) fields are changed. (The reader sources these from the plist;
    /// updating `Properties.apdb`'s search index is a later refinement.)
    public func setIPTC(versionUuid uuid: String, caption: String? = nil,
                        title: String? = nil, byline: String? = nil,
                        copyright: String? = nil) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: true)
        guard let plistURL = try locateVersionPlist(forVersionUuid: uuid, using: db) else {
            throw WriteError.plistNotFound(uuid)
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: &format) as? [String: Any] else { return }
        var iptc = plist["iptcProperties"] as? [String: Any] ?? [:]
        if let c = caption { iptc["Caption"] = c; iptc["Caption/Abstract"] = c }
        if let t = title { iptc["Title"] = t; iptc["ObjectName"] = t }
        if let b = byline { iptc["Byline"] = b }
        if let cp = copyright { iptc["CopyrightNotice"] = cp }
        plist["iptcProperties"] = iptc
        plist["plistWriteTimestamp"] = Date()
        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try out.write(to: plistURL, options: .atomic)
    }

    // MARK: - Structure (projects / albums)

    /// Creates a new project under the "Projects" container and returns its uuid.
    @discardableResult
    public func createProject(named name: String) throws -> String {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let mid = try nextModelId("RKFolder", db)
        let uuid = UUID().uuidString
        let parentPath = (try db.query(
            "SELECT folderPath FROM RKFolder WHERE uuid = 'AllProjectsItem'")
            .first?["folderPath"]?.stringValue) ?? "1/2/"
        let path = "\(parentPath)\(mid)/"
        try db.execute("""
            INSERT INTO RKFolder(modelId, uuid, folderType, name, parentFolderUuid,
                versionCount, folderPath, createDate, isInTrash)
            VALUES (?, ?, 2, ?, 'AllProjectsItem', 0, ?, ?, 0)
            """, [.integer(Int64(mid)), .text(uuid), .text(name), .text(path),
                  .real(Date().timeIntervalSinceReferenceDate)])
        return uuid
    }

    /// Creates a new regular (user) album and returns its uuid.
    @discardableResult
    public func createAlbum(named name: String, inFolderUuid folder: String = "LibraryFolder") throws -> String {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let mid = try nextModelId("RKAlbum", db)
        let uuid = UUID().uuidString
        try db.execute("""
            INSERT INTO RKAlbum(modelId, uuid, name, albumType, albumSubclass,
                folderUuid, isMagic, isInTrash)
            VALUES (?, ?, ?, 1, 3, ?, 0, 0)
            """, [.integer(Int64(mid)), .text(uuid), .text(name), .text(folder)])
        return uuid
    }

    /// Moves a version (and its master) to another project.
    public func moveVersion(_ versionUuid: String, toProject projectUuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let masterUuid = try db.query("SELECT masterUuid FROM RKVersion WHERE uuid = ?",
                                      [.text(versionUuid)]).first?["masterUuid"]?.stringValue
        try db.execute("UPDATE RKVersion SET projectUuid = ? WHERE uuid = ?",
                       [.text(projectUuid), .text(versionUuid)])
        if let masterUuid {
            try db.execute("UPDATE RKMaster SET projectUuid = ? WHERE uuid = ?",
                           [.text(projectUuid), .text(masterUuid)])
        }
    }

    /// Deletes a user album (the album + its membership rows; photos remain).
    public func deleteAlbum(_ uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        if let amid = try db.query("SELECT modelId FROM RKAlbum WHERE uuid = ?", [.text(uuid)])
            .first?["modelId"]?.intValue {
            try db.execute("DELETE FROM RKAlbumVersion WHERE albumId = ?", [.integer(Int64(amid))])
        }
        try db.execute("DELETE FROM RKAlbum WHERE uuid = ?", [.text(uuid)])
    }

    /// Deletes a project: moves its versions to the trash, then removes the
    /// folder row. (Photos are recoverable from the trash until emptied.)
    public func deleteProject(_ uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        try db.execute("UPDATE RKVersion SET isInTrash = 1 WHERE projectUuid = ?", [.text(uuid)])
        try db.execute("UPDATE RKFolder SET isInTrash = 1 WHERE uuid = ?", [.text(uuid)])
    }

    // MARK: - Stacks

    /// Creates a stack from the given versions, returning the stack uuid.
    @discardableResult
    public func createStack(versionUuids: [String], pick: String? = nil) throws -> String {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        guard !versionUuids.isEmpty else { return "" }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let stackUuid = UUID().uuidString
        for (i, vu) in versionUuids.enumerated() {
            let mid = try nextModelId("RKStackContent", db)
            try db.execute("INSERT INTO RKStackContent(modelId, stackUuid, versionUuid, orderNumber) VALUES (?, ?, ?, ?)",
                           [.integer(Int64(mid)), .text(stackUuid), .text(vu), .integer(Int64(i))])
            try db.execute("UPDATE RKVersion SET stackUuid = ? WHERE uuid = ?", [.text(stackUuid), .text(vu)])
        }
        let sid = try nextModelId("RKStackState", db)
        try db.execute("INSERT INTO RKStackState(modelId, stackUuid, albumUuid, albumPick, isExpanded) VALUES (?, ?, NULL, ?, 1)",
                       [.integer(Int64(sid)), .text(stackUuid), .text(pick ?? versionUuids[0])])
        return stackUuid
    }

    /// Unstacks: removes the stack and clears its versions' stack reference.
    public func breakStack(_ stackUuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        try db.execute("UPDATE RKVersion SET stackUuid = NULL WHERE stackUuid = ?", [.text(stackUuid)])
        try db.execute("DELETE FROM RKStackContent WHERE stackUuid = ?", [.text(stackUuid)])
        try db.execute("DELETE FROM RKStackState WHERE stackUuid = ?", [.text(stackUuid)])
    }

    /// Sets which version is the stack's pick (the one shown when collapsed).
    public func setStackPick(_ versionUuid: String, inStack stackUuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        try db.execute("UPDATE RKStackState SET albumPick = ? WHERE stackUuid = ?",
                       [.text(versionUuid), .text(stackUuid)])
    }

    /// Renames a project (RKFolder).
    public func renameProject(_ uuid: String, to name: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        try db.execute("UPDATE RKFolder SET name = ? WHERE uuid = ?", [.text(name), .text(uuid)])
    }

    /// Renames an album (RKAlbum).
    public func renameAlbum(_ uuid: String, to name: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        try db.execute("UPDATE RKAlbum SET name = ? WHERE uuid = ?", [.text(name), .text(uuid)])
    }

    /// Adds a version to a regular album (no-op if already a member).
    public func addVersion(_ versionUuid: String, toAlbumUuid albumUuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let versionId = try versionModelId(versionUuid, db)
        guard let albumId = try db.query(
            "SELECT modelId FROM RKAlbum WHERE uuid = ?", [.text(albumUuid)])
            .first?["modelId"]?.intValue else { return }
        let existing = try db.query(
            "SELECT 1 FROM RKAlbumVersion WHERE versionId = ? AND albumId = ?",
            [.integer(Int64(versionId)), .integer(Int64(albumId))])
        if existing.isEmpty {
            let mid = try nextModelId("RKAlbumVersion", db)
            try db.execute(
                "INSERT INTO RKAlbumVersion(modelId, versionId, albumId) VALUES (?, ?, ?)",
                [.integer(Int64(mid)), .integer(Int64(versionId)), .integer(Int64(albumId))])
        }
    }

    /// Duplicates a version (same master, new version row), returning the new
    /// version's uuid. The copy starts unrated/unflagged with no adjustments,
    /// like Aperture's "Duplicate Version".
    @discardableResult
    public func duplicateVersion(_ uuid: String) throws -> String {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let rows = try db.query("""
            SELECT name, fileName, masterUuid, projectUuid, imageDate, masterWidth,
                   masterHeight, rotation, stackUuid, exifLatitude, exifLongitude
            FROM RKVersion WHERE uuid = ?
            """, [.text(uuid)])
        guard let r = rows.first, let masterUuid = r["masterUuid"]?.stringValue else {
            throw WriteError.versionNotFound(uuid)
        }
        let nextVer = (try db.query(
            "SELECT COALESCE(MAX(versionNumber), 0) + 1 AS n FROM RKVersion WHERE masterUuid = ?",
            [.text(masterUuid)]).first?["n"]?.intValue) ?? 2
        let newUuid = UUID().uuidString
        let mid = try nextModelId("RKVersion", db)
        func v(_ k: String) -> SQLiteDatabase.Value { r[k] ?? .null }
        try db.execute("""
            INSERT INTO RKVersion(modelId, uuid, name, fileName, versionNumber, masterUuid, projectUuid,
                imageDate, mainRating, isFlagged, isOriginal, isEditable, colorLabelIndex,
                masterWidth, masterHeight, rotation, hasAdjustments, hasKeywords, createDate,
                isInTrash, showInLibrary, exifLatitude, exifLongitude)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 1, -1, ?, ?, ?, 0, 0, ?, 0, 1, ?, ?)
            """, [.integer(Int64(mid)), .text(newUuid), v("name"), v("fileName"),
                  .integer(Int64(nextVer)), .text(masterUuid), v("projectUuid"), v("imageDate"),
                  v("masterWidth"), v("masterHeight"), v("rotation"),
                  .real(Date().timeIntervalSinceReferenceDate),
                  v("exifLatitude"), v("exifLongitude")])
        return newUuid
    }

    // MARK: - Import

    /// Imports an image file into a project as a managed master (copies the file
    /// into the library's `Masters/` tree and authors `RKMaster`/`RKVersion`).
    /// Returns the new version's uuid. Thumbnails/EXIF plists aren't generated
    /// yet — the reader falls back to decoding the master for display.
    @discardableResult
    public func importImage(at source: URL, intoProject projectUuid: String,
                            fileName: String? = nil) throws -> String {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let fm = FileManager.default

        let attrs = try? fm.attributesOfItem(atPath: source.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let fileSize = (attrs?[.size] as? Int) ?? 0

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy/MM/dd"
        let stampFmt = DateFormatter(); stampFmt.dateFormat = "yyyyMMdd-HHmmss"
        let datePath = "\(dayFmt.string(from: date))/\(stampFmt.string(from: date))"

        let mastersDir = libraryURL.appendingPathComponent("Masters").appendingPathComponent(datePath)
        try fm.createDirectory(at: mastersDir, withIntermediateDirectories: true)

        let baseName = fileName ?? source.lastPathComponent
        var dest = mastersDir.appendingPathComponent(baseName)
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            let stem = (baseName as NSString).deletingPathExtension
            let ext = (baseName as NSString).pathExtension
            dest = mastersDir.appendingPathComponent("\(stem)-\(counter).\(ext)")
            counter += 1
        }
        try fm.copyItem(at: source, to: dest)

        let imagePath = "\(datePath)/\(dest.lastPathComponent)"
        let size = ImageLoader.pixelSize(at: dest)
        let width = Int(size?.width ?? 0)
        let height = Int(size?.height ?? 0)
        let name = (dest.lastPathComponent as NSString).deletingPathExtension
        let appleDate = date.timeIntervalSinceReferenceDate

        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let masterUuid = UUID().uuidString
        let masterMid = try nextModelId("RKMaster", db)
        try db.execute("""
            INSERT INTO RKMaster(modelId, uuid, name, projectUuid, fileName, originalFileName,
                type, fileIsReference, isMissing, imagePath, fileSize, imageDate, createDate, isInTrash)
            VALUES (?, ?, ?, ?, ?, ?, 'IMGT', 0, 0, ?, ?, ?, ?, 0)
            """, [.integer(Int64(masterMid)), .text(masterUuid), .text(name), .text(projectUuid),
                  .text(dest.lastPathComponent), .text(baseName), .text(imagePath),
                  .integer(Int64(fileSize)), .real(appleDate), .real(appleDate)])

        let gps = ImageLoader.gpsCoordinate(at: dest)
        let latVal: SQLiteDatabase.Value = gps.map { .real($0.latitude) } ?? .null
        let lonVal: SQLiteDatabase.Value = gps.map { .real($0.longitude) } ?? .null

        let versionUuid = UUID().uuidString
        let versionMid = try nextModelId("RKVersion", db)
        try db.execute("""
            INSERT INTO RKVersion(modelId, uuid, name, fileName, versionNumber, masterUuid, projectUuid,
                imageDate, mainRating, isFlagged, isOriginal, isEditable, colorLabelIndex,
                masterWidth, masterHeight, rotation, hasAdjustments, hasKeywords, createDate, isInTrash, showInLibrary,
                exifLatitude, exifLongitude)
            VALUES (?, ?, ?, ?, 1, ?, ?, ?, 0, 0, 1, 1, -1, ?, ?, 0, 0, 0, ?, 0, 1, ?, ?)
            """, [.integer(Int64(versionMid)), .text(versionUuid), .text(name),
                  .text(dest.lastPathComponent), .text(masterUuid), .text(projectUuid),
                  .real(appleDate), .integer(Int64(width)), .integer(Int64(height)), .real(appleDate),
                  latVal, lonVal])

        // Best-effort: generate a cached thumbnail + a Version-1.apversion plist
        // (EXIF + proxy paths) so imported photos browse fast and show metadata.
        try? writeImportDerivatives(masterURL: dest, masterUuid: masterUuid,
                                    versionUuid: versionUuid, name: name,
                                    projectUuid: projectUuid, datePath: datePath)
        return versionUuid
    }

    private func writeImportDerivatives(masterURL: URL, masterUuid: String,
                                        versionUuid: String, name: String,
                                        projectUuid: String, datePath: String) throws {
        let fm = FileManager.default

        // Thumbnail under Thumbnails/<date>/<thumbUuid>/thumb_<name>_1024.jpg
        let thumbUuid = UUID().uuidString
        let thumbDir = libraryURL.appendingPathComponent("Thumbnails")
            .appendingPathComponent(datePath).appendingPathComponent(thumbUuid)
        try fm.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbName = "thumb_\(name)_1024.jpg"
        let thumbSize = ImageLoader.writeJPEGThumbnail(
            from: masterURL, to: thumbDir.appendingPathComponent(thumbName), maxPixel: 1024)
        let thumbRel = "\(datePath)/\(thumbUuid)/\(thumbName)"

        // Version-1.apversion plist beside the master's version folder.
        var plist: [String: Any] = [
            "uuid": versionUuid, "name": name, "versionNumber": 1,
            "masterUuid": masterUuid, "projectUuid": projectUuid,
            "mainRating": 0, "isFlagged": false,
            "exifProperties": ImageLoader.exifSummary(at: masterURL),
            "iptcProperties": ["StarRating": "0"]
        ]
        if let s = thumbSize {
            plist["imageProxyState"] = [
                "thumbnailPath": thumbRel, "miniThumbnailPath": thumbRel,
                "thumbnailWidth": Int(s.width), "thumbnailHeight": Int(s.height)
            ]
        }
        let versionDir = libraryURL.appendingPathComponent("Database/Versions")
            .appendingPathComponent(datePath).appendingPathComponent(masterUuid)
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: versionDir.appendingPathComponent("Version-1.apversion"))
    }

    // MARK: - Trash (reversible)

    /// Moves a version to the trash (sets `isInTrash`). Reversible with
    /// `restoreFromTrash`. Does not delete any files.
    public func moveToTrash(versionUuid uuid: String) throws {
        try updateVersion(uuid: uuid,
                          columns: ["isInTrash": .integer(1)],
                          plistKeys: ["isInTrash": true],
                          iptcStarRating: nil)
    }

    /// Restores a version from the trash.
    public func restoreFromTrash(versionUuid uuid: String) throws {
        try updateVersion(uuid: uuid,
                          columns: ["isInTrash": .integer(0)],
                          plistKeys: ["isInTrash": false],
                          iptcStarRating: nil)
    }

    /// PERMANENTLY deletes a version: removes its catalog rows and, if no other
    /// version references its master, the master row, the original file, and the
    /// version plist folder. Irreversible — back up first. No-op if the version
    /// doesn't exist.
    public func permanentlyDelete(versionUuid uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)

        let vrows = try db.query(
            "SELECT modelId, masterUuid FROM RKVersion WHERE uuid = ?", [.text(uuid)])
        guard let v = vrows.first,
              let modelId = v["modelId"]?.intValue,
              let masterUuid = v["masterUuid"]?.stringValue else { return }

        let mrows = try db.query(
            "SELECT imagePath FROM RKMaster WHERE uuid = ?", [.text(masterUuid)])
        let imagePath = mrows.first?["imagePath"]?.stringValue

        // Remove association + version rows.
        try db.execute("DELETE FROM RKKeywordForVersion WHERE versionId = ?", [.integer(Int64(modelId))])
        try db.execute("DELETE FROM RKAlbumVersion WHERE versionId = ?", [.integer(Int64(modelId))])
        try db.execute("DELETE FROM RKStackContent WHERE versionUuid = ?", [.text(uuid)])
        try db.execute("DELETE FROM RKVersion WHERE uuid = ?", [.text(uuid)])

        // If the master now has no versions, delete it and its files.
        let remaining = try db.query(
            "SELECT 1 FROM RKVersion WHERE masterUuid = ?", [.text(masterUuid)])
        if remaining.isEmpty {
            try db.execute("DELETE FROM RKMaster WHERE uuid = ?", [.text(masterUuid)])
            if let imagePath {
                let fm = FileManager.default
                let masterURL = libraryURL.appendingPathComponent("Masters").appendingPathComponent(imagePath)
                try? fm.removeItem(at: masterURL)
                let datePath = (imagePath as NSString).deletingLastPathComponent
                let versionDir = libraryURL
                    .appendingPathComponent("Database/Versions")
                    .appendingPathComponent(datePath)
                    .appendingPathComponent(masterUuid)
                try? fm.removeItem(at: versionDir)
            }
        }
    }

    /// Empties the trash by permanently deleting every trashed version. Returns
    /// the number of versions removed. Irreversible — back up first.
    @discardableResult
    public func emptyTrash() throws -> Int {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: true)
        let rows = try db.query("SELECT uuid FROM RKVersion WHERE isInTrash = 1")
        let uuids = rows.compactMap { $0["uuid"]?.stringValue }
        for uuid in uuids { try permanentlyDelete(versionUuid: uuid) }
        return uuids.count
    }

    // MARK: - Keywords

    /// Assigns a keyword (by name) to a version, creating the keyword in the
    /// vocabulary if it doesn't exist. No-op if already assigned.
    ///
    /// NOTE: keywords are written to the catalog (`RKKeyword` /
    /// `RKKeywordForVersion` / `RKVersion.hasKeywords`), which is what OpenLens
    /// reads. Mirroring into the `.apversion` plist is tracked on the roadmap.
    public func addKeyword(_ name: String, toVersion uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)

        let versionId = try versionModelId(uuid, db)
        let keywordId = try findOrCreateKeyword(trimmed, db)

        let existing = try db.query(
            "SELECT 1 FROM RKKeywordForVersion WHERE versionId = ? AND keywordId = ?",
            [.integer(Int64(versionId)), .integer(Int64(keywordId))])
        if existing.isEmpty {
            let mid = try nextModelId("RKKeywordForVersion", db)
            try db.execute(
                "INSERT INTO RKKeywordForVersion (modelId, versionId, keywordId) VALUES (?, ?, ?)",
                [.integer(Int64(mid)), .integer(Int64(versionId)), .integer(Int64(keywordId))])
        }
        try db.execute("UPDATE RKVersion SET hasKeywords = 1 WHERE uuid = ?", [.text(uuid)])
    }

    /// Removes a keyword (by name) from a version. No-op if not assigned.
    public func removeKeyword(_ name: String, fromVersion uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let versionId = try versionModelId(uuid, db)
        let kw = try db.query(
            "SELECT modelId FROM RKKeyword WHERE searchName = ?",
            [.text(name.lowercased())])
        guard let keywordId = kw.first?["modelId"]?.intValue else { return }
        try db.execute(
            "DELETE FROM RKKeywordForVersion WHERE versionId = ? AND keywordId = ?",
            [.integer(Int64(versionId)), .integer(Int64(keywordId))])
        let remaining = try db.query(
            "SELECT 1 FROM RKKeywordForVersion WHERE versionId = ?",
            [.integer(Int64(versionId))])
        try db.execute("UPDATE RKVersion SET hasKeywords = ? WHERE uuid = ?",
                       [.integer(remaining.isEmpty ? 0 : 1), .text(uuid)])
    }

    /// Replaces a version's keywords with exactly `names`.
    public func setKeywords(_ names: [String], forVersion uuid: String) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let versionId = try versionModelId(uuid, db)
        try db.execute("DELETE FROM RKKeywordForVersion WHERE versionId = ?",
                       [.integer(Int64(versionId))])
        try db.execute("UPDATE RKVersion SET hasKeywords = 0 WHERE uuid = ?", [.text(uuid)])
        for name in names { try addKeyword(name, toVersion: uuid) }
    }

    // MARK: - Keyword helpers

    private func versionModelId(_ uuid: String, _ db: SQLiteDatabase) throws -> Int {
        let rows = try db.query("SELECT modelId FROM RKVersion WHERE uuid = ?", [.text(uuid)])
        guard let id = rows.first?["modelId"]?.intValue else {
            throw WriteError.versionNotFound(uuid)
        }
        return id
    }

    private func nextModelId(_ table: String, _ db: SQLiteDatabase) throws -> Int {
        let rows = try db.query("SELECT COALESCE(MAX(modelId), 0) + 1 AS next FROM \(table)")
        return rows.first?["next"]?.intValue ?? 1
    }

    private func findOrCreateKeyword(_ name: String, _ db: SQLiteDatabase) throws -> Int {
        let found = try db.query(
            "SELECT modelId FROM RKKeyword WHERE searchName = ?", [.text(name.lowercased())])
        if let id = found.first?["modelId"]?.intValue { return id }
        let mid = try nextModelId("RKKeyword", db)
        try db.execute("""
            INSERT INTO RKKeyword (modelId, uuid, name, searchName, parentId, hasChildren, shortcut)
            VALUES (?, ?, ?, ?, NULL, 0, NULL)
            """, [.integer(Int64(mid)), .text(UUID().uuidString),
                  .text(name), .text(name.lowercased())])
        return mid
    }

    // MARK: - Core update

    private func updateVersion(uuid: String,
                               columns: [String: SQLiteDatabase.Value],
                               plistKeys: [String: Any],
                               iptcStarRating: Int?) throws {
        guard allowWrites else { throw WriteError.writesNotAllowed }

        // 1. Update the SQLite catalog.
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        let assignments = columns.keys.map { "\($0) = ?" }.joined(separator: ", ")
        let params = Array(columns.values) + [SQLiteDatabase.Value.text(uuid)]
        try db.execute("UPDATE RKVersion SET \(assignments) WHERE uuid = ?", params)

        // 2. Update the per-version plist so Aperture (and our own reads of the
        //    plist) stay consistent.
        if let plistURL = try locateVersionPlist(forVersionUuid: uuid, using: db) {
            try patchPlist(at: plistURL, with: plistKeys, iptcStarRating: iptcStarRating)
        }
    }

    /// Finds the `Version-N.apversion` file for a version uuid. We resolve the
    /// master's storage folder from the catalog, then match by the version's
    /// own uuid recorded inside each plist.
    private func locateVersionPlist(forVersionUuid uuid: String,
                                    using db: SQLiteDatabase) throws -> URL? {
        let rows = try db.query("""
            SELECT v.fileName AS fileName, v.versionNumber AS versionNumber,
                   m.imagePath AS imagePath
            FROM RKVersion v
            JOIN RKMaster m ON m.uuid = v.masterUuid
            WHERE v.uuid = ?
            """, [.text(uuid)])
        guard let row = rows.first,
              let imagePath = row["imagePath"]?.stringValue else {
            throw WriteError.versionNotFound(uuid)
        }
        // imagePath looks like "2026/06/16/20260616-214247/F30A1132.JPG".
        // The version plists live under Database/Versions/<same date path>/
        // <masterUuid>/Version-N.apversion. We search that date folder.
        let datePath = (imagePath as NSString).deletingLastPathComponent
        let searchDir = libraryURL
            .appendingPathComponent("Database/Versions")
            .appendingPathComponent(datePath)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: searchDir,
                                             includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "apversion" {
            if let data = try? Data(contentsOf: fileURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               (plist["uuid"] as? String) == uuid {
                return fileURL
            }
        }
        throw WriteError.plistNotFound(uuid)
    }

    private func patchPlist(at url: URL,
                            with keys: [String: Any],
                            iptcStarRating: Int?) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        let data = try Data(contentsOf: url)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: &format) as? [String: Any] else {
            return
        }
        for (k, v) in keys { plist[k] = v }
        if let star = iptcStarRating {
            var iptc = plist["iptcProperties"] as? [String: Any] ?? [:]
            iptc["StarRating"] = String(star)
            plist["iptcProperties"] = iptc
        }
        plist["plistWriteTimestamp"] = Date()
        let out = try PropertyListSerialization.data(
            fromPropertyList: plist, format: format, options: 0)
        try out.write(to: url, options: .atomic)
    }

    // Aperture ratings run -1 (Rejected) through 5 stars.
    private func clampRating(_ r: Int) -> Int { max(-1, min(5, r)) }
}
