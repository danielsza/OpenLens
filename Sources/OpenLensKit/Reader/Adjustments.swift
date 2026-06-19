import Foundation

public extension ApertureLibrary {

    /// Adjustments recorded against a photo's version, in apply order.
    func adjustments(for photo: Photo) throws -> [Adjustment] {
        guard tableExists("RKImageAdjustment") else { return [] }
        let rows = try libraryDB.query("""
            SELECT uuid, name, versionUuid, adjIndex, isEnabled, data
            FROM RKImageAdjustment
            WHERE versionUuid = ?
            ORDER BY adjIndex
            """, [.text(photo.version.id)])
        return rows.map { row in
            Adjustment(
                id: row["uuid"]?.stringValue ?? "",
                rawName: row["name"]?.stringValue ?? "",
                versionUuid: row["versionUuid"]?.stringValue ?? "",
                index: row["adjIndex"]?.intValue ?? 0,
                isEnabled: (row["isEnabled"]?.intValue ?? 0) == 1,
                data: row["data"]?.dataValue
            )
        }
    }

    /// Friendly names of the *enabled* adjustments on a photo (for display).
    func enabledAdjustmentNames(for photo: Photo) throws -> [String] {
        try adjustments(for: photo).filter { $0.isEnabled }.map { $0.displayName }
    }
}
