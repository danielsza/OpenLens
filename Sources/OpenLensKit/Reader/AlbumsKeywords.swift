import Foundation

public extension ApertureLibrary {

    // MARK: - Albums

    /// All albums not in the trash.
    func albums() throws -> [Album] {
        guard tableExists("RKAlbum") else { return [] }
        let rows = try libraryDB.query("""
            SELECT modelId, uuid, name, albumType, albumSubclass,
                   folderUuid, isMagic, isInTrash
            FROM RKAlbum
            WHERE isInTrash = 0 OR isInTrash IS NULL
            ORDER BY name
            """)
        return rows.map { row in
            Album(
                id: row["uuid"]?.stringValue ?? "",
                modelId: row["modelId"]?.intValue ?? 0,
                name: row["name"]?.stringValue,
                albumType: row["albumType"]?.intValue ?? 0,
                albumSubclass: row["albumSubclass"]?.intValue ?? 0,
                folderUuid: row["folderUuid"]?.stringValue,
                isMagic: (row["isMagic"]?.intValue ?? 0) == 1,
                isInTrash: (row["isInTrash"]?.intValue ?? 0) == 1
            )
        }
    }

    /// Albums the user created (excludes implicit and smart/system albums).
    func userAlbums() throws -> [Album] {
        try albums().filter { !$0.isSystem && ($0.name?.isEmpty == false) }
    }

    /// Photos belonging to a regular album, via `RKAlbumVersion`.
    func photos(inAlbum album: Album) throws -> [Photo] {
        guard tableExists("RKAlbumVersion") else { return [] }
        let idRows = try libraryDB.query(
            "SELECT versionId FROM RKAlbumVersion WHERE albumId = ?",
            [.integer(Int64(album.modelId))])
        let ids = Set(idRows.compactMap { $0["versionId"]?.intValue })
        guard !ids.isEmpty else { return [] }
        return try photos().filter { ids.contains($0.version.modelId) }
    }

    // MARK: - Keywords

    /// The full keyword vocabulary (a tree, linked by `parentModelId`).
    func keywordVocabulary() throws -> [Keyword] {
        guard tableExists("RKKeyword") else { return [] }
        let rows = try libraryDB.query("""
            SELECT modelId, uuid, name, parentId, hasChildren
            FROM RKKeyword
            ORDER BY name
            """)
        return rows.map { row in
            Keyword(
                id: row["uuid"]?.stringValue ?? "",
                modelId: row["modelId"]?.intValue ?? 0,
                name: row["name"]?.stringValue ?? "",
                parentModelId: row["parentId"]?.intValue,
                hasChildren: (row["hasChildren"]?.intValue ?? 0) == 1
            )
        }
    }

    /// Keyword names assigned to a specific photo (via `RKKeywordForVersion`).
    func keywords(for photo: Photo) throws -> [String] {
        guard tableExists("RKKeywordForVersion"), tableExists("RKKeyword") else { return [] }
        let rows = try libraryDB.query("""
            SELECT k.name AS name
            FROM RKKeyword k
            JOIN RKKeywordForVersion kv ON kv.keywordId = k.modelId
            WHERE kv.versionId = ?
            ORDER BY k.name
            """, [.integer(Int64(photo.version.modelId))])
        return rows.compactMap { $0["name"]?.stringValue }
    }
}
