import Foundation

/// One point of a brush stroke, in MASTER pixel coordinates (bottom-left
/// origin, matching crop coordinates).
public struct OLBrushPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A brush stroke: a polyline of points stamped with a soft round brush.
public struct OLBrushStroke: Codable, Equatable {
    public var points: [OLBrushPoint]
    /// Brush radius in master pixels.
    public var radius: Double
    /// 0 = hard edge, 1 = fully feathered.
    public var softness: Double
    /// Stroke opacity 0…1.
    public var flow: Double
    /// Erase strokes remove from the mask instead of adding.
    public var erase: Bool

    public init(points: [OLBrushPoint], radius: Double,
                softness: Double = 0.5, flow: Double = 1, erase: Bool = false) {
        self.points = points
        self.radius = radius
        self.softness = softness
        self.flow = flow
        self.erase = erase
    }
}

/// A grayscale mask built from brush strokes (white = affected).
public struct OLMask: Codable, Equatable {
    public var strokes: [OLBrushStroke]
    public init(strokes: [OLBrushStroke] = []) { self.strokes = strokes }
    public var isEmpty: Bool { strokes.allSatisfy { $0.points.isEmpty || $0.erase } }
}

/// A local (masked) adjustment layer: parameters applied only where the mask
/// is white. Geometry fields in `params` are ignored for layers.
public struct OLLocalAdjustment: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var params: OLAdjustments
    public var mask: OLMask

    public init(id: String = UUID().uuidString, name: String = "Brush",
                enabled: Bool = true, params: OLAdjustments = OLAdjustments(),
                mask: OLMask = OLMask()) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.params = params
        self.mask = mask
    }

    public static func encodeList(_ layers: [OLLocalAdjustment]) throws -> Data {
        try JSONEncoder().encode(layers)
    }

    public static func decodeList(_ data: Data) -> [OLLocalAdjustment]? {
        try? JSONDecoder().decode([OLLocalAdjustment].self, from: data)
    }
}

public extension ApertureLibrary {
    /// The adjustment-row name for OpenLens local (masked) adjustment layers.
    static let olLocalAdjustmentName = "OLLocalAdjustmentsV1"

    /// OpenLens local adjustment layers for a photo, if any.
    func olLocalAdjustments(for photo: Photo) -> [OLLocalAdjustment] {
        guard tableExists("RKImageAdjustment") else { return [] }
        guard let rows = try? libraryDB.query("""
            SELECT data FROM RKImageAdjustment
            WHERE versionUuid = ? AND name = ? AND isEnabled = 1
            """, [.text(photo.version.id), .text(Self.olLocalAdjustmentName)]),
              let data = rows.first?["data"]?.dataValue else { return [] }
        return OLLocalAdjustment.decodeList(data) ?? []
    }
}
