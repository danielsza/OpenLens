// Generates the OpenLens app icon (an aperture-blade lens on dark grey).
// Run: swift scripts/make_icon.swift <output.png> [size]
import Foundation
import CoreGraphics
import ImageIO

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
let s = CGFloat(S)
let center = CGPoint(x: s / 2, y: s / 2)

// Rounded-rect dark background (macOS icon style).
let bg = CGPath(roundedRect: CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88),
                cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
ctx.addPath(bg)
ctx.setFillColor(CGColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1))
ctx.fillPath()

// Outer lens ring.
ctx.setStrokeColor(CGColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1))
ctx.setLineWidth(s * 0.025)
ctx.strokeEllipse(in: CGRect(x: s * 0.16, y: s * 0.16, width: s * 0.68, height: s * 0.68))

// Six aperture blades.
let bladeCount = 6
let R = s * 0.30            // blade outer radius
let inner = s * 0.10        // aperture opening
ctx.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1))
for i in 0..<bladeCount {
    let a0 = CGFloat(i) * (2 * .pi / CGFloat(bladeCount))
    let a1 = a0 + (2 * .pi / CGFloat(bladeCount)) * 0.88
    let mid = (a0 + a1) / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x + cos(a0) * R, y: center.y + sin(a0) * R))
    path.addArc(center: center, radius: R, startAngle: a0, endAngle: a1, clockwise: false)
    path.addLine(to: CGPoint(x: center.x + cos(mid + 0.5) * inner,
                             y: center.y + sin(mid + 0.5) * inner))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
}

// Aperture opening.
ctx.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                           width: inner * 2, height: inner * 2))

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                           "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out) (\(S)x\(S))")
