import Foundation
import CoreGraphics
import CoreImage

/// Renders `OLAdjustments` onto an image with Core Image, non-destructively.
public enum AdjustmentRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Applies the parameters to a CGImage. Returns the input unchanged when
    /// the parameters are neutral or rendering fails.
    ///
    /// `masterPixelSize`: the ORIGINAL master's pixel dimensions. Crop
    /// coordinates are stored in master space; when rendering a downsampled
    /// image they are scaled by `cg.width / masterWidth`. Pass nil when `cg`
    /// is the full-resolution master (scale 1).
    public static func apply(_ params: OLAdjustments, to cg: CGImage,
                             masterPixelSize: CGSize? = nil) -> CGImage {
        guard !params.isIdentity else { return cg }
        var image = CIImage(cgImage: cg)

        // Geometry first (straighten around the centre, then crop), so colour
        // work runs on the final pixels only.
        if params.straighten != 0 {
            let radians = params.straighten * .pi / 180
            let extent = image.extent
            let rotate = CGAffineTransform(translationX: extent.midX, y: extent.midY)
                .rotated(by: radians)
                .translatedBy(x: -extent.midX, y: -extent.midY)
            image = image.transformed(by: rotate).cropped(to: extent)
        }
        if params.hasCrop {
            let scale = masterPixelSize.map { Double(cg.width) / max(1, $0.width) } ?? 1
            let rect = CGRect(x: params.cropX * scale, y: params.cropY * scale,
                              width: params.cropWidth * scale, height: params.cropHeight * scale)
                .intersection(image.extent)
            if !rect.isEmpty {
                image = image.cropped(to: rect)
                // Re-origin so subsequent rendering starts at (0,0).
                image = image.transformed(by: CGAffineTransform(
                    translationX: -rect.origin.x, y: -rect.origin.y))
            }
        }

        if params.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust",
                                         parameters: [kCIInputEVKey: params.exposure])
        }
        if params.contrast != 1 || params.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: params.contrast,
                kCIInputSaturationKey: params.saturation,
                kCIInputBrightnessKey: 0
            ])
        }
        if params.temperature != 0 || params.tint != 0 {
            // Neutral is (6500, 0); map our -100...100 ranges onto sensible shifts.
            let targetTemp = 6500 - params.temperature * 30   // warm(+) lowers CCT target
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: targetTemp, y: params.tint)
            ])
        }
        if params.highlights != 0 || params.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 - params.highlights * 0.7,   // 1 = neutral
                "inputShadowAmount": params.shadows                     // 0 = neutral
            ])
        }
        if params.sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: params.sharpness
            ])
        }

        guard let out = context.createCGImage(image, from: image.extent) else {
            return cg
        }
        return out
    }
}
