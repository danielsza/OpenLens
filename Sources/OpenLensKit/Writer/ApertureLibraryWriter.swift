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

    private func clampRating(_ r: Int) -> Int { max(0, min(5, r)) }
}
