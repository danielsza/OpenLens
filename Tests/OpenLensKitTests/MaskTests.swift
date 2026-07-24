import XCTest
import CoreGraphics
@testable import OpenLensKit

final class MaskTests: XCTestCase {

    private func grayImage(_ width: Int, _ height: Int, gray: CGFloat) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func pixels(_ cg: CGImage) -> [UInt8] {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    func testRasterizerPaintsWhereStroked() throws {
        let mask = OLMask(strokes: [
            OLBrushStroke(points: [OLBrushPoint(x: 50, y: 50)], radius: 20,
                          softness: 0.2, flow: 1)
        ])
        let cg = try XCTUnwrap(MaskRasterizer.rasterize(
            mask, masterSize: CGSize(width: 100, height: 100),
            targetSize: CGSize(width: 100, height: 100)))
        let px = pixels(cg)
        let center = Int(px[(50 * 100 + 50) * 4])
        let corner = Int(px[(5 * 100 + 5) * 4])
        XCTAssertGreaterThan(center, 200, "stroke centre should be near-white")
        XCTAssertLessThan(corner, 10, "unpainted corner should stay black")
    }

    func testRasterizerScalesFromMasterSpace() throws {
        // Stroke at master (200,200) r=40; rendered at half size → (100,100) r=20.
        let mask = OLMask(strokes: [
            OLBrushStroke(points: [OLBrushPoint(x: 200, y: 200)], radius: 40, softness: 0)
        ])
        let cg = try XCTUnwrap(MaskRasterizer.rasterize(
            mask, masterSize: CGSize(width: 400, height: 400),
            targetSize: CGSize(width: 200, height: 200)))
        let px = pixels(cg)
        // CG row 0 is the TOP; master y=200 (bottom-left origin) → row 100.
        XCTAssertGreaterThan(Int(px[(100 * 200 + 100) * 4]), 200)
        XCTAssertLessThan(Int(px[(100 * 200 + 180) * 4]), 10)
    }

    func testLocalLayerAffectsOnlyMaskedRegion() {
        // Brighten a vertical band on the left via a masked exposure layer.
        var boost = OLAdjustments(); boost.exposure = 1.5
        let layer = OLLocalAdjustment(
            params: boost,
            mask: OLMask(strokes: [
                OLBrushStroke(points: [OLBrushPoint(x: 25, y: 0), OLBrushPoint(x: 25, y: 100)],
                              radius: 25, softness: 0.1, flow: 1)
            ]))
        let out = AdjustmentRenderer.applyStack(
            global: OLAdjustments(), layers: [layer],
            to: grayImage(100, 100, gray: 0.35),
            masterPixelSize: CGSize(width: 100, height: 100))
        let px = pixels(out)
        func mean(xRange: Range<Int>) -> Double {
            var total = 0.0, n = 0.0
            for y in 40..<60 { for x in xRange {
                total += Double(px[(y * out.width + x) * 4]); n += 1
            }}
            return total / n
        }
        let left = mean(xRange: 10..<35)
        let right = mean(xRange: 70..<95)
        XCTAssertGreaterThan(left, right + 25,
                             "masked left band should be brighter (left \(left), right \(right))")
    }

    func testLocalAdjustmentsRoundTripThroughCatalog() throws {
        guard let src = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY")
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("masks-\(UUID().uuidString).aplibrary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: src), to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lib = try ApertureLibrary(url: tmp)
        let photo = try XCTUnwrap(try lib.photos().first)
        var params = OLAdjustments(); params.saturation = 1.4
        let layers = [OLLocalAdjustment(
            name: "Sky", params: params,
            mask: OLMask(strokes: [
                OLBrushStroke(points: [OLBrushPoint(x: 10, y: 10)], radius: 8)
            ]))]

        let writer = ApertureLibraryWriter(libraryURL: tmp, allowWrites: true)
        try writer.setOLLocalAdjustments(layers, forVersion: photo.version.id)

        let reread = try ApertureLibrary(url: tmp)
        let photo2 = try XCTUnwrap(try reread.photos().first { $0.id == photo.id })
        XCTAssertEqual(reread.olLocalAdjustments(for: photo2), layers)
        XCTAssertTrue(photo2.version.hasAdjustments)

        // Empty list removes the row.
        try writer.setOLLocalAdjustments([], forVersion: photo.version.id)
        let reread2 = try ApertureLibrary(url: tmp)
        let photo3 = try XCTUnwrap(try reread2.photos().first { $0.id == photo.id })
        XCTAssertTrue(reread2.olLocalAdjustments(for: photo3).isEmpty)
    }
}
