import Foundation

/// OpenLens's own non-destructive adjustment parameters.
///
/// Stored as a JSON blob in an `RKImageAdjustment` row named
/// `OLAdjustmentsV1` — same table Aperture used, our own format. Values are
/// chosen so `0` (or `1` for multipliers) means "no change".
public struct OLAdjustments: Codable, Equatable {
    public var exposure: Double = 0      // EV, -2...+2
    public var contrast: Double = 1      // 0.5...1.5 (1 = neutral)
    public var saturation: Double = 1    // 0...2 (1 = neutral)
    public var temperature: Double = 0   // -100...+100 (warm/cool shift)
    public var tint: Double = 0          // -100...+100 (green/magenta)
    public var highlights: Double = 0    // -1...+1
    public var shadows: Double = 0       // -1...+1
    public var sharpness: Double = 0     // 0...1

    public init() {}

    /// True when every parameter is at its neutral value.
    public var isIdentity: Bool { self == OLAdjustments() }

    public func encodedJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) -> OLAdjustments? {
        try? JSONDecoder().decode(OLAdjustments.self, from: data)
    }

    /// Stable hash for cache keys.
    public var cacheKey: String {
        (try? encodedJSON()).map { String($0.hashValue) } ?? "id"
    }
}

public extension ApertureLibrary {
    /// The internal adjustment-row name OpenLens uses.
    static let olAdjustmentName = "OLAdjustmentsV1"

    /// OpenLens-native adjustments for a photo, if any.
    func olAdjustments(for photo: Photo) -> OLAdjustments? {
        guard tableExists("RKImageAdjustment") else { return nil }
        guard let rows = try? libraryDB.query("""
            SELECT data FROM RKImageAdjustment
            WHERE versionUuid = ? AND name = ? AND isEnabled = 1
            """, [.text(photo.version.id), .text(Self.olAdjustmentName)]),
              let data = rows.first?["data"]?.dataValue else { return nil }
        return OLAdjustments.decode(data)
    }
}
