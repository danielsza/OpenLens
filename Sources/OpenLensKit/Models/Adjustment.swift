import Foundation

/// A non-destructive adjustment recorded against a version (`RKImageAdjustment`).
///
/// Aperture stores each edit (exposure, white balance, crop, …) as a row whose
/// `name` is the internal class name and whose `data` blob holds the parameters
/// (often an `NSKeyedArchiver` archive). OpenLens currently *reads* these — it
/// can list which adjustments exist and whether they're enabled. Decoding every
/// parameter and re-rendering with Core Image is the next step (see ROADMAP).
public struct Adjustment: Identifiable, Hashable {
    public let id: String          // uuid
    public let rawName: String     // e.g. "RKExposureAdjustment"
    public let versionUuid: String
    public let index: Int          // adjIndex (apply order)
    public let isEnabled: Bool
    public let data: Data?

    public var type: AdjustmentType { AdjustmentType(rawName: rawName) }
    public var displayName: String { type.displayName }

    /// Best-effort numeric parameters, available when `data` is a plain binary
    /// plist of values. Returns empty for `NSKeyedArchiver` archives (which need
    /// full unarchiving — a later milestone).
    public func numericParameters() -> [String: Double] {
        guard let data,
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return [:] }
        if dict["$archiver"] != nil { return [:] }   // keyed archive, skip
        var out: [String: Double] = [:]
        for (k, v) in dict {
            if let n = v as? NSNumber { out[k] = n.doubleValue }
        }
        return out
    }
}

/// Friendly classification of Aperture's adjustment class names.
public enum AdjustmentType: Hashable {
    case exposure, whiteBalance, contrast, saturation, highlightsShadows
    case crop, straighten, sharpen, noiseReduction, vignette
    case levels, curves, retouch, redEye, chromaBlur, devignette
    case other(String)

    public init(rawName: String) {
        switch rawName {
        case "RKExposureAdjustment": self = .exposure
        case "RKWhiteBalanceAdjustment": self = .whiteBalance
        case "RKContrastAdjustment": self = .contrast
        case "RKSaturationAdjustment": self = .saturation
        case "RKHighlightsShadowsAdjustment": self = .highlightsShadows
        case "RKCropOperation": self = .crop
        case "RKStraightenOperation", "RKStraightenAdjustment": self = .straighten
        case "RKSharpenEdgesAdjustment", "RKEdgeSharpenAdjustment", "RKSharpenAdjustment": self = .sharpen
        case "RKNoiseReductionAdjustment": self = .noiseReduction
        case "RKVignetteAdjustment": self = .vignette
        case "RKDevignetteAdjustment": self = .devignette
        case "RKLevelsAdjustment": self = .levels
        case "RKCurvesAdjustment": self = .curves
        case "RKRetouchOperation", "RKRetouchAdjustment": self = .retouch
        case "RKRedEyeAdjustment", "RKRedEyeOperation": self = .redEye
        case "RKChromaBlurAdjustment": self = .chromaBlur
        default: self = .other(rawName)
        }
    }

    public var displayName: String {
        switch self {
        case .exposure: return "Exposure"
        case .whiteBalance: return "White Balance"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .highlightsShadows: return "Highlights & Shadows"
        case .crop: return "Crop"
        case .straighten: return "Straighten"
        case .sharpen: return "Sharpen"
        case .noiseReduction: return "Noise Reduction"
        case .vignette: return "Vignette"
        case .devignette: return "Devignette"
        case .levels: return "Levels"
        case .curves: return "Curves"
        case .retouch: return "Retouch"
        case .redEye: return "Red-Eye"
        case .chromaBlur: return "Chroma Blur"
        case .other(let raw):
            // Strip the RK prefix and Adjustment/Operation suffix for display.
            var s = raw
            if s.hasPrefix("RK") { s.removeFirst(2) }
            for suffix in ["Adjustment", "Operation"] where s.hasSuffix(suffix) {
                s.removeLast(suffix.count)
            }
            return s.isEmpty ? raw : s
        }
    }
}
