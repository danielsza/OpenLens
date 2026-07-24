import Foundation
import CoreGraphics
import CoreImage

/// Renders `OLAdjustments` (and masked local layers) onto an image with
/// Core Image, non-destructively.
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
        applyStack(global: params, layers: [], to: cg, masterPixelSize: masterPixelSize)
    }

    /// Applies local (masked) layers first, then the global adjustments
    /// (geometry + colour). Layer geometry fields are ignored.
    public static func applyStack(global: OLAdjustments, layers: [OLLocalAdjustment],
                                  to cg: CGImage, masterPixelSize: CGSize? = nil) -> CGImage {
        let activeLayers = layers.filter { $0.enabled && !$0.mask.isEmpty && !$0.params.isIdentity }
        guard !global.isIdentity || !activeLayers.isEmpty else { return cg }

        var image = CIImage(cgImage: cg)
        let renderedSize = CGSize(width: cg.width, height: cg.height)
        let master = masterPixelSize ?? renderedSize

        // 1. Local layers (colour-only, blended through their masks).
        for layer in activeLayers {
            guard let maskCG = MaskRasterizer.rasterize(layer.mask, masterSize: master,
                                                        targetSize: renderedSize) else { continue }
            let adjusted = colorPipeline(image, layer.params)
            image = adjusted.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: CIImage(cgImage: maskCG)
            ])
        }

        // 2. Global geometry (straighten about the centre, then crop).
        if global.straighten != 0 {
            let radians = global.straighten * .pi / 180
            let extent = image.extent
            let rotate = CGAffineTransform(translationX: extent.midX, y: extent.midY)
                .rotated(by: radians)
                .translatedBy(x: -extent.midX, y: -extent.midY)
            image = image.transformed(by: rotate).cropped(to: extent)
        }
        if global.hasCrop {
            let scale = Double(cg.width) / max(1, master.width)
            let rect = CGRect(x: global.cropX * scale, y: global.cropY * scale,
                              width: global.cropWidth * scale, height: global.cropHeight * scale)
                .intersection(image.extent)
            if !rect.isEmpty {
                image = image.cropped(to: rect)
                image = image.transformed(by: CGAffineTransform(
                    translationX: -rect.origin.x, y: -rect.origin.y))
            }
        }

        // 3. Global colour.
        image = colorPipeline(image, global)

        guard let out = context.createCGImage(image, from: image.extent) else {
            return cg
        }
        return out
    }

    /// The colour portion of the pipeline (no geometry).
    private static func colorPipeline(_ input: CIImage, _ params: OLAdjustments) -> CIImage {
        var image = input
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
        return image
    }
}
