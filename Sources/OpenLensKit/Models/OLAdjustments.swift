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
    /// Straighten angle in degrees (positive = counter-clockwise), like
    /// Aperture's `inputRotation`.
    public var straighten: Double = 0    // -45...+45
    /// Crop rectangle in MASTER pixel coordinates, bottom-left origin
    /// (Aperture/Core Image convention). Width/height 0 = no crop.
    public var cropX: Double = 0
    public var cropY: Double = 0
    public var cropWidth: Double = 0
    public var cropHeight: Double = 0

    public var hasCrop: Bool { cropWidth > 0 && cropHeight > 0 }

    public init() {}

    /// Tolerant decoding: fields added over time default to neutral so blobs
    /// saved by older OpenLens versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        straighten = try c.decodeIfPresent(Double.self, forKey: .straighten) ?? 0
        cropX = try c.decodeIfPresent(Double.self, forKey: .cropX) ?? 0
        cropY = try c.decodeIfPresent(Double.self, forKey: .cropY) ?? 0
        cropWidth = try c.decodeIfPresent(Double.self, forKey: .cropWidth) ?? 0
        cropHeight = try c.decodeIfPresent(Double.self, forKey: .cropHeight) ?? 0
    }

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
