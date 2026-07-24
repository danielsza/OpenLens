import Foundation
import CoreGraphics
import CoreImage

/// RAW Fine Tuning parameters (subset of Aperture's `RKRawDecodeOperation`
/// mapped onto Apple's modern `CIRAWFilter` pipeline).
public struct RawFineTuning: Equatable {
    /// Local tone-map boost, 0…1 (1 = Apple default rendering).
    public var boost: Double = 1
    /// RAW-stage sharpening, 0…1 (nil = filter default).
    public var sharpness: Double?

    public init(boost: Double = 1, sharpness: Double? = nil) {
        self.boost = boost
        self.sharpness = sharpness
    }

    /// Extracts tuning from a decoded Aperture RAW Fine Tuning operation.
    public init?(from operation: ApertureEditOperation) {
        guard operation.identifier == "RKRawDecodeOperation",
              !operation.parameters.isEmpty else { return nil }
        let p = operation.parameters
        boost = min(1, max(0, p["inputBoostAmount"] ?? 1))
        if (p["inputSharpenEnabled"] ?? 0) != 0, let s = p["inputSharpenIntensity"] {
            sharpness = min(1, max(0, s))
        }
    }
}

/// Decodes RAW files through `CIRAWFilter` so fine-tuning parameters apply at
/// the RAW-development stage (not as post-processing on the demosaiced image).
public enum RawRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// File extensions treated as camera RAW.
    public static let rawExtensions: Set<String> =
        ["cr2", "cr3", "nef", "nrw", "arw", "dng", "orf", "raf", "rw2", "pef", "srw", "3fr"]

    public static func isRawFile(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased())
    }

    /// Renders a RAW file with the given tuning. Returns nil for non-RAW
    /// input or decode failure (callers fall back to ImageIO).
    public static func render(at url: URL, tuning: RawFineTuning = RawFineTuning(),
                              maxPixelSize: Int = 0) -> CGImage? {
        guard isRawFile(url), let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.boostAmount = Float(tuning.boost)
        if let sharpness = tuning.sharpness {
            filter.sharpnessAmount = Float(sharpness)
        }
        if maxPixelSize > 0 {
            let natural = filter.nativeSize
            let largest = max(natural.width, natural.height)
            if largest > 0 {
                filter.scaleFactor = Float(min(1, CGFloat(maxPixelSize) / largest))
            }
        }
        guard let output = filter.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return cg
    }
}
