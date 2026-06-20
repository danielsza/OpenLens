import XCTest
import CoreGraphics
@testable import OpenLensKit

/// ImageIO decode tests, run against a real library when OPENLENS_TEST_LIBRARY
/// is set (skipped otherwise).
final class ImagingTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run imaging tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testDecodesDisplayImages() throws {
        let lib = try openTestLibrary()
        for photo in try lib.photos() {
            let url = lib.displayImageURL(for: photo)
            XCTAssertTrue(ImageLoader.canDecode(url), "Cannot decode \(url.lastPathComponent)")
            let cg = ImageLoader.cgImage(at: url, maxPixelSize: 256)
            XCTAssertNotNil(cg, "No CGImage for \(photo.version.name)")
            if let cg {
                // Downsampled long edge must respect the requested cap (allow a
                // little slack for aspect rounding).
                XCTAssertLessThanOrEqual(max(cg.width, cg.height), 300)
            }
        }
    }

    func testHistogram() throws {
        let lib = try openTestLibrary()
        let photo = try XCTUnwrap(try lib.photos().first)
        let h = try XCTUnwrap(ImageLoader.histogram(at: lib.masterFileURL(for: photo.master)))
        XCTAssertEqual(h.bucketCount, 64)
        let sR = h.red.reduce(0, +), sL = h.luminance.reduce(0, +)
        XCTAssertGreaterThan(sL, 0)
        XCTAssertEqual(sR, sL)   // same pixel count across channels
    }

    func testReadsPixelSize() throws {
        let lib = try openTestLibrary()
        let photo = try XCTUnwrap(try lib.photos().first)
        let size = ImageLoader.pixelSize(at: lib.masterFileURL(for: photo.master))
        XCTAssertNotNil(size)
        if let size { XCTAssertGreaterThan(size.width, 0) }
    }
}
