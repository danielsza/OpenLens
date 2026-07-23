import Foundation
import CryptoKit

public extension ApertureLibrary {

    /// Finds photos whose master files are byte-identical duplicates.
    ///
    /// Two-phase for speed on large libraries: group by file size first, then
    /// SHA-256 only the size collisions. (Aperture's own `imageHash` column is
    /// empty in real libraries, so we hash content ourselves.)
    /// Returns groups of 2+ photos sharing identical master bytes.
    func findDuplicates() throws -> [[Photo]] {
        let fm = FileManager.default
        // One representative photo per master, so versions of the same master
        // aren't reported as duplicates of each other.
        var seenMasters = Set<String>()
        let photos = try photos().filter { seenMasters.insert($0.master.id).inserted }

        var bySize: [Int: [Photo]] = [:]
        for photo in photos where !photo.master.isReference {
            let url = masterFileURL(for: photo.master)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else { continue }
            bySize[size, default: []].append(photo)
        }

        var groups: [[Photo]] = []
        for (_, candidates) in bySize where candidates.count > 1 {
            var byHash: [String: [Photo]] = [:]
            for photo in candidates {
                let url = masterFileURL(for: photo.master)
                guard let data = try? Data(contentsOf: url) else { continue }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                byHash[hash, default: []].append(photo)
            }
            for (_, dupes) in byHash where dupes.count > 1 {
                groups.append(dupes.sorted { $0.version.name < $1.version.name })
            }
        }
        return groups.sorted { ($0.first?.version.name ?? "") < ($1.first?.version.name ?? "") }
    }
}
