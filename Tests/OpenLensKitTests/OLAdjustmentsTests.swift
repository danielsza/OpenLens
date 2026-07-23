import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class OLAdjustmentsTests: XCTestCase {

    private func makePNG(_ url: URL, gray: CGFloat) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 24, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    private func meanLuma(_ cg: CGImage) -> Double {
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = data.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                      bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var total = 0.0
        var i = 0
        while i < data.count {
            total += 0.299 * Double(data[i]) + 0.587 * Double(data[i+1]) + 0.114 * Double(data[i+2])
            i += 4
        }
        return total / Double(cg.width * cg.height)
    }

    func testRendererBrightensWithPositiveExposure() throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("adj-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src, gray: 0.4)
        let cg = try XCTUnwrap(ImageLoader.cgImage(at: src, maxPixelSize: 100))
        var p = OLAdjustments(); p.exposure = 1.0
        let out = AdjustmentRenderer.apply(p, to: cg)
        XCTAssertGreaterThan(meanLuma(out), meanLuma(cg) + 10,
                             "+1EV should brighten noticeably")
        // Identity params return the input unchanged.
        XCTAssertEqual(meanLuma(AdjustmentRenderer.apply(OLAdjustments(), to: cg)),
                       meanLuma(cg), accuracy: 0.5)
    }

    func testSaveLoadClearRoundTrip() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-oladj-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src, gray: 0.5)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let v = try writer.importImage(at: src, intoProject: project)

        var p = OLAdjustments(); p.exposure = 0.7; p.saturation = 1.3
        try writer.setOLAdjustments(p, forVersion: v)

        var lib = try ApertureLibrary(url: libURL)
        var photo = try XCTUnwrap(try lib.photos().first { $0.id == v })
        XCTAssertTrue(photo.version.hasAdjustments)
        XCTAssertEqual(lib.olAdjustments(for: photo), p)

        // Update in place.
        p.contrast = 1.2
        try writer.setOLAdjustments(p, forVersion: v)
        lib = try ApertureLibrary(url: libURL)
        photo = try XCTUnwrap(try lib.photos().first { $0.id == v })
        XCTAssertEqual(lib.olAdjustments(for: photo)?.contrast ?? 0, 1.2, accuracy: 0.0001)

        // Identity clears.
        try writer.setOLAdjustments(OLAdjustments(), forVersion: v)
        lib = try ApertureLibrary(url: libURL)
        photo = try XCTUnwrap(try lib.photos().first { $0.id == v })
        XCTAssertNil(lib.olAdjustments(for: photo))
        XCTAssertFalse(photo.version.hasAdjustments)
    }
}
