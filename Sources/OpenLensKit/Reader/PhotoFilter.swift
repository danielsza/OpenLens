import Foundation

/// A pure, composable filter over photos — the basis of an Aperture-style
/// filter bar. Kept UI-free so it can be tested and reused.
public struct PhotoFilter: Equatable {
    /// Minimum star rating (0 keeps everything).
    public var minRating: Int = 0
    /// Keep only flagged photos.
    public var flaggedOnly: Bool = false
    /// Keep only photos with this colour label (nil = any).
    public var colorLabel: Int?
    /// Keep only edited photos.
    public var adjustedOnly: Bool = false
    /// Case-insensitive substring match on the version name (empty = any).
    public var nameContains: String = ""

    public init(minRating: Int = 0,
                flaggedOnly: Bool = false,
                colorLabel: Int? = nil,
                adjustedOnly: Bool = false,
                nameContains: String = "") {
        self.minRating = minRating
        self.flaggedOnly = flaggedOnly
        self.colorLabel = colorLabel
        self.adjustedOnly = adjustedOnly
        self.nameContains = nameContains
    }

    /// True if no constraints are active.
    public var isEmpty: Bool {
        minRating == 0 && !flaggedOnly && colorLabel == nil
            && !adjustedOnly && nameContains.isEmpty
    }

    public func matches(_ photo: Photo) -> Bool {
        let v = photo.version
        if v.rating < minRating { return false }
        if flaggedOnly && !v.isFlagged { return false }
        if let label = colorLabel, v.colorLabel != label { return false }
        if adjustedOnly && !v.hasAdjustments { return false }
        if !nameContains.isEmpty,
           v.name.range(of: nameContains, options: .caseInsensitive) == nil {
            return false
        }
        return true
    }

    public func apply(to photos: [Photo]) -> [Photo] {
        isEmpty ? photos : photos.filter(matches)
    }
}
