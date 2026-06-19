import Foundation

/// Browser sort orders, matching Aperture's sort options.
public enum PhotoSort: String, CaseIterable, Identifiable {
    case date = "Date"
    case name = "Name"
    case rating = "Rating"
    case fileName = "File Name"
    public var id: String { rawValue }
}

public extension Array where Element == Photo {
    /// Returns the photos sorted by the given key. Ties fall back to file name
    /// for a stable, predictable order.
    func sorted(by sort: PhotoSort, ascending: Bool = true) -> [Photo] {
        let ordered = sorted { a, b in
            switch sort {
            case .date:
                let da = a.version.imageDate ?? .distantPast
                let db = b.version.imageDate ?? .distantPast
                if da != db { return da < db }
            case .name:
                let c = a.version.name.localizedCaseInsensitiveCompare(b.version.name)
                if c != .orderedSame { return c == .orderedAscending }
            case .rating:
                if a.version.rating != b.version.rating { return a.version.rating < b.version.rating }
            case .fileName:
                break
            }
            return a.master.fileName.localizedCaseInsensitiveCompare(b.master.fileName) == .orderedAscending
        }
        return ascending ? ordered : ordered.reversed()
    }
}
