import Foundation

/// How to bucket photos by capture date.
public enum DateGranularity {
    case day, month, year
}

/// A titled group of photos (e.g. one day's shots).
public struct PhotoSection: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let date: Date?     // representative date (nil for the "no date" bucket)
    public let photos: [Photo]
}

public extension Array where Element == Photo {

    /// Groups photos by capture date at the given granularity, returning
    /// sections in chronological order. Photos without a date are collected in
    /// a final "Unknown Date" section.
    func grouped(by granularity: DateGranularity,
                 calendar: Calendar = .current) -> [PhotoSection] {
        var buckets: [Date: [Photo]] = [:]
        var undated: [Photo] = []

        for photo in self {
            guard let date = photo.version.imageDate else { undated.append(photo); continue }
            let key = Self.bucketDate(date, granularity, calendar)
            buckets[key, default: []].append(photo)
        }

        var sections = buckets.keys.sorted().map { key in
            PhotoSection(
                id: ISO8601DateFormatter().string(from: key),
                title: Self.title(for: key, granularity, calendar),
                date: key,
                photos: buckets[key]!
            )
        }
        if !undated.isEmpty {
            sections.append(PhotoSection(id: "unknown", title: "Unknown Date",
                                         date: nil, photos: undated))
        }
        return sections
    }

    /// Groups photos (by capture time) into runs where each photo is within
    /// `gapSeconds` of the previous — the basis for auto-stacking.
    func autoStackGroups(gapSeconds: TimeInterval) -> [[Photo]] {
        let ordered = sorted { ($0.version.imageDate ?? .distantPast) < ($1.version.imageDate ?? .distantPast) }
        var groups: [[Photo]] = []
        var current: [Photo] = []
        var last: Date?
        for p in ordered {
            let d = p.version.imageDate
            if let last, let d, d.timeIntervalSince(last) <= gapSeconds {
                current.append(p)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [p]
            }
            if let d { last = d }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func bucketDate(_ date: Date, _ g: DateGranularity,
                                   _ cal: Calendar) -> Date {
        let comps: Set<Calendar.Component>
        switch g {
        case .day: comps = [.year, .month, .day]
        case .month: comps = [.year, .month]
        case .year: comps = [.year]
        }
        return cal.date(from: cal.dateComponents(comps, from: date)) ?? date
    }

    private static func title(for date: Date, _ g: DateGranularity,
                              _ cal: Calendar) -> String {
        let f = DateFormatter()
        switch g {
        case .day: f.dateStyle = .medium; f.timeStyle = .none
        case .month: f.dateFormat = "LLLL yyyy"
        case .year: f.dateFormat = "yyyy"
        }
        return f.string(from: date)
    }
}
