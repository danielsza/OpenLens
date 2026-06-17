import Foundation

public extension ApertureLibrary {

    /// Free-text search across a photo's name, keywords, and camera/lens
    /// metadata. Case-insensitive; all whitespace-separated terms must match
    /// (AND). Returns photos in the library's default order.
    ///
    /// This reads per-photo metadata/keywords, so it is convenient rather than
    /// fast; a future index will speed it up for large libraries.
    func search(_ query: String, in photos: [Photo]? = nil) throws -> [Photo] {
        let terms = query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let pool = try photos ?? self.photos()
        guard !terms.isEmpty else { return pool }

        return try pool.filter { photo in
            var haystack = photo.version.name.lowercased()
            if let m = metadata(for: photo) {
                haystack += " " + [m.cameraMake, m.cameraModel, m.lensModel]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")
            }
            let keywords = (try? keywords(for: photo)) ?? []
            haystack += " " + keywords.joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}
