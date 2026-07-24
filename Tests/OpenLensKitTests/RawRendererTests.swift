import XCTest
import CoreGraphics
@testable import OpenLensKit

final class RawRendererTests: XCTestCase {

    private var cr2URL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/raw/_MG_0840.CR2")
    }

    private func meanLuminance(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total = 0.0
        for i in stride(from: 0, to: data.count, by: 4) {
            total += 0.299 * Double(data[i]) + 0.587 * Double(data[i + 1]) + 0.114 * Double(data[i + 2])
        }
        return total / Double(w * h)
    }

    func testRendersRealCR2ThroughRawPipeline() throws {
        guard FileManager.default.fileExists(atPath: cr2URL.path) else {
            throw XCTSkip("CR2 fixture not present")
        }
        XCTAssertTrue(RawRenderer.isRawFile(cr2URL))
        let cg = try XCTUnwrap(RawRenderer.render(at: cr2URL, maxPixelSize: 320))
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 400)
        XCTAssertGreaterThan(min(cg.width, cg.height), 100)
    }

    func testBoostChangesRendering() throws {
        guard FileManager.default.fileExists(atPath: cr2URL.path) else {
            throw XCTSkip("CR2 fixture not present")
        }
        let boosted = try XCTUnwrap(RawRenderer.render(
            at: cr2URL, tuning: RawFineTuning(boost: 1), maxPixelSize: 200))
        let flat = try XCTUnwrap(RawRenderer.render(
            at: cr2URL, tuning: RawFineTuning(boost: 0), maxPixelSize: 200))
        // Boost applies a tone curve — the renders must differ measurably.
        XCTAssertNotEqual(meanLuminance(boosted), meanLuminance(flat), accuracy: 0.5)
    }

    func testNonRawReturnsNil() {
        let jpeg = FileManager.default.temporaryDirectory.appendingPathComponent("x.jpg")
        XCTAssertNil(RawRenderer.render(at: jpeg))
        XCTAssertFalse(RawRenderer.isRawFile(jpeg))
    }

    func testTuningFromRealRawDecodeOperation() {
        let op = ApertureEditOperation(
            id: "r", identifier: "RKRawDecodeOperation", displayName: "RAW Fine Tuning",
            enabled: true,
            parameters: ["inputBoostAmount": 0.62, "inputSharpenEnabled": 1,
                         "inputSharpenIntensity": 0.35])
        let tuning = RawFineTuning(from: op)
        XCTAssertEqual(tuning?.boost ?? -1, 0.62, accuracy: 0.0001)
        XCTAssertEqual(tuning?.sharpness ?? -1, 0.35, accuracy: 0.0001)

        let empty = ApertureEditOperation(
            id: "e", identifier: "RKRawDecodeOperation", displayName: "RAW Fine Tuning",
            enabled: true, parameters: [:])
        XCTAssertNil(RawFineTuning(from: empty))
    }
}
