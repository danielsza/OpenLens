import Foundation
import CoreGraphics
import CoreImage

/// Renders `OLAdjustments` onto an image with Core Image, non-destructively.
public enum AdjustmentRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Applies the parameters to a CGImage. Returns the input unchanged when
    /// the parameters are neutral or rendering fails.
    public static func apply(_ params: OLAdjustments, to cg: CGImage) -> CGImage {
        guard !params.isIdentity else { return cg }
        var image = CIImage(cgImage: cg)

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

        guard let out = context.createCGImage(image, from: CIImage(cgImage: cg).extent) else {
            return cg
        }
        return out
    }
}
