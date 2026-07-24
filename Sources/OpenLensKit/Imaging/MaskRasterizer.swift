import Foundation
import CoreGraphics

/// Rasterizes an `OLMask`'s brush strokes into a grayscale image
/// (white = fully affected), scaled from master coordinates to a target size.
public enum MaskRasterizer {

    /// Renders the mask at `targetSize` (the rendered image's pixel size).
    /// Stroke coordinates/radii are in master space and are scaled by
    /// `targetSize.width / masterSize.width`.
    public static func rasterize(_ mask: OLMask, masterSize: CGSize,
                                 targetSize: CGSize) -> CGImage? {
        let width = max(1, Int(targetSize.width))
        let height = max(1, Int(targetSize.height))
        guard masterSize.width > 0,
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        let scale = targetSize.width / masterSize.width
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for stroke in mask.strokes {
            let radius = max(1, stroke.radius * scale)
            let gray: CGFloat = stroke.erase ? 0 : 1
            let alpha = CGFloat(min(1, max(0, stroke.flow)))
            let softness = CGFloat(min(1, max(0, stroke.softness)))
            // Solid core out to (1 − softness) of the radius, then falloff.
            let core = max(0.01, 1 - softness)
            let colors = [CGColor(gray: gray, alpha: alpha),
                          CGColor(gray: gray, alpha: alpha),
                          CGColor(gray: gray, alpha: 0)]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                            colors: colors as CFArray,
                                            locations: [0, core, 1]) else { continue }
            for point in interpolated(stroke.points, spacing: radius * 0.4) {
                let center = CGPoint(x: point.x * scale, y: point.y * scale)
                ctx.saveGState()
                if stroke.erase {
                    // Erasing paints black at flow strength over the mask.
                    ctx.setBlendMode(.normal)
                } else {
                    // Additive so overlapping stamps build to full strength.
                    ctx.setBlendMode(.lighten)
                }
                ctx.drawRadialGradient(gradient,
                                       startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius,
                                       options: [])
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }

    /// Densifies a polyline so brush stamps overlap smoothly.
    private static func interpolated(_ points: [OLBrushPoint],
                                     spacing: CGFloat) -> [OLBrushPoint] {
        guard points.count > 1, spacing > 0 else { return points }
        var out: [OLBrushPoint] = []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = (dx * dx + dy * dy).squareRoot()
            let steps = max(1, Int(dist / spacing))
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                out.append(OLBrushPoint(x: a.x + dx * t, y: a.y + dy * t))
            }
        }
        out.append(points[points.count - 1])
        return out
    }
}
