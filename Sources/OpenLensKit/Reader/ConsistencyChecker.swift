import Foundation

/// Checks a library's catalog↔disk integrity and reports problems without
/// changing anything. The basis for a future "repair" feature.
public struct ConsistencyReport: Equatable {
    public enum Issue: Equatable, CustomStringConvertible {
        case missingMasterFile(versionName: String, path: String)
        case orphanVersion(versionUuid: String)          // version's master row missing
        case missingThumbnail(versionName: String)       // plist references a thumb that isn't on disk
        case missingVersionPlist(versionName: String)
        case danglingAlbumEntry(versionId: Int)          // album membership to a nonexistent version
        case danglingKeywordEntry(versionId: Int)

        public var description: String {
            switch self {
            case .missingMasterFile(let n, let p): return "Missing master file for \(n): \(p)"
            case .orphanVersion(let u): return "Version \(u) has no master record"
            case .missingThumbnail(let n): return "Missing thumbnail for \(n)"
            case .missingVersionPlist(let n): return "Missing .apversion plist for \(n)"
            case .danglingAlbumEntry(let id): return "Album entry references missing version \(id)"
            case .danglingKeywordEntry(let id): return "Keyword entry references missing version \(id)"
            }
        }
    }

    public var photosChecked = 0
    public var issues: [Issue] = []
    public var isHealthy: Bool { issues.isEmpty }
}

public extension ApertureLibrary {

    /// Runs all consistency checks and returns a report.
    func checkConsistency() throws -> ConsistencyReport {
        var report = ConsistencyReport()
        let fm = FileManager.default
        let masters = try mastersByUuid()
        let allVersions = try versions(includeHidden: true)
        let live = try photos()
        report.photosChecked = live.count

        // Versions must resolve to a master row; live masters must exist on disk.
        for v in allVersions where masters[v.masterUuid] == nil {
            report.issues.append(.orphanVersion(versionUuid: v.id))
        }
        for photo in live where !photo.master.isReference {
            let url = masterFileURL(for: photo.master)
            if !fm.fileExists(atPath: url.path) {
                report.issues.append(.missingMasterFile(versionName: photo.version.name,
                                                        path: photo.master.imagePath))
            }
            // Plist + referenced thumbnail.
            if let meta = metadata(for: photo) {
                if let rel = meta.thumbnailPath {
                    let t = thumbnailsURL.appendingPathComponent(rel)
                    if !fm.fileExists(atPath: t.path) {
                        report.issues.append(.missingThumbnail(versionName: photo.version.name))
                    }
                }
            } else {
                report.issues.append(.missingVersionPlist(versionName: photo.version.name))
            }
        }

        // Dangling membership rows.
        let versionIds = Set(allVersions.map { $0.modelId })
        if tableExists("RKAlbumVersion") {
            for row in try libraryDB.query("SELECT DISTINCT versionId FROM RKAlbumVersion") {
                if let id = row["versionId"]?.intValue, !versionIds.contains(id) {
                    report.issues.append(.danglingAlbumEntry(versionId: id))
                }
            }
        }
        if tableExists("RKKeywordForVersion") {
            for row in try libraryDB.query("SELECT DISTINCT versionId FROM RKKeywordForVersion") {
                if let id = row["versionId"]?.intValue, !versionIds.contains(id) {
                    report.issues.append(.danglingKeywordEntry(versionId: id))
                }
            }
        }
        return report
    }
}
