import XCTest
import CoreGraphics
@testable import OpenLensKit

/// Export tests, run against a real library when OPENLENS_TEST_LIBRARY is set
/// (skipped otherwise). They write into a temp directory that is cleaned up.
final class ExporterTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run exporter tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openlens-export-\(UUID().uuidString)")
        return dir
    }

    func testExportsOriginals() throws {
        let lib = try openTestLibrary()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = Exporter(library: lib)
        let photo = try XCTUnwrap(try lib.photos().first)
        let url = try exporter.export(photo, to: dir, mode: .originals)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan((try Data(contentsOf: url)).count, 0)
    }

    func testExportsRenderedJPEG() throws {
        let lib = try openTestLibrary()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = Exporter(library: lib)
        let photo = try XCTUnwrap(try lib.photos().first)
        let url = try exporter.export(photo, to: dir,
                                      mode: .rendered(maxPixelSize: 128, quality: 0.8))
        XCTAssertEqual(url.pathExtension, "jpg")
        let decoded = try XCTUnwrap(ImageLoader.cgImage(at: url, maxPixelSize: 256))
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 160)
    }

    func testBatchExportAndUniqueNaming() throws {
        let lib = try openTestLibrary()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exporter = Exporter(library: lib)
        let photos = try lib.photos()
        // Export twice to force the unique-naming path on the second pass.
        _ = exporter.exportBatch(photos, to: dir, mode: .originals)
        let second = exporter.exportBatch(photos, to: dir, mode: .originals)
        XCTAssertTrue(second.failures.isEmpty)
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents.count, photos.count * 2)
    }
}
