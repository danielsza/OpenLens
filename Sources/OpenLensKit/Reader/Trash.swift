import Foundation

public extension ApertureLibrary {

    /// Photos currently in the trash (`RKVersion.isInTrash = 1`).
    func trashedPhotos() throws -> [Photo] {
        let masters = try mastersByUuid()
        let rows = try libraryDB.query("""
            SELECT modelId, uuid, name, fileName, versionNumber, masterUuid,
                   projectUuid, mainRating, isFlagged, colorLabelIndex,
                   hasAdjustments, isOriginal, rotation, isInTrash,
                   showInLibrary, imageDate, masterWidth, masterHeight, stackUuid,
                   hasKeywords
            FROM RKVersion
            WHERE isInTrash = 1
            ORDER BY imageDate, fileName
            """)
        return rows.compactMap { row in
            let v = Self.makeVersion(from: row)
            guard let m = masters[v.masterUuid] else { return nil }
            return Photo(version: v, master: m)
        }
    }
}
