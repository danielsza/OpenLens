import Foundation

/// Aggregate counts for a library — powers an overview screen and the CLI.
public struct LibraryStatistics: Equatable {
    public var projectCount = 0
    public var albumCount = 0          // user albums only
    public var photoCount = 0          // live versions
    public var masterCount = 0
    public var referencedMasterCount = 0
    public var keywordCount = 0        // vocabulary size
    public var stackCount = 0
    public var flaggedCount = 0
    public var editedCount = 0
    /// rating (0...5) -> number of photos.
    public var ratingHistogram: [Int: Int] = [:]
}

public extension ApertureLibrary {

    func statistics() throws -> LibraryStatistics {
        var s = LibraryStatistics()
        let photos = try photos()
        let masters = try mastersByUuid()

        s.projectCount = try projects().count
        s.albumCount = (try? userAlbums().count) ?? 0
        s.photoCount = photos.count
        s.masterCount = masters.count
        s.referencedMasterCount = masters.values.filter { $0.isReference }.count
        s.keywordCount = (try? keywordVocabulary().count) ?? 0
        s.stackCount = (try? stacks().count) ?? 0
        s.flaggedCount = photos.filter { $0.version.isFlagged }.count
        s.editedCount = photos.filter { $0.version.hasAdjustments }.count

        var hist: [Int: Int] = [:]
        for photo in photos {
            hist[photo.version.rating, default: 0] += 1
        }
        s.ratingHistogram = hist
        return s
    }
}
