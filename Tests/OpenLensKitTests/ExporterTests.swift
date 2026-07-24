import XCTest
import CoreGraphics
import ImageIO
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

    func testExportWithSettingsFormatsAndWatermark() throws {
        let lib = try openTestLibrary()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let exporter = Exporter(library: lib)
        let photo = try XCTUnwrap(try lib.photos().first)

        // PNG, resized.
        let png = try exporter.export(photo, to: dir,
            settings: ExportSettings(format: .png, maxPixelSize: 100))
        XCTAssertEqual(png.pathExtension, "png")
        XCTAssertTrue(ImageLoader.canDecode(png))

        // HEIC.
        let heic = try exporter.export(photo, to: dir,
            settings: ExportSettings(format: .heic, maxPixelSize: 100, jpegQuality: 0.8))
        XCTAssertEqual(heic.pathExtension, "heic")
        XCTAssertTrue(ImageLoader.canDecode(heic))

        // JPEG with a text watermark + DPI.
        let jpg = try exporter.export(photo, to: dir,
            settings: ExportSettings(format: .jpeg, maxPixelSize: 200, jpegQuality: 0.8,
                                     dpi: 300, watermark: Watermark(text: "© Test", position: .bottomRight)))
        XCTAssertEqual(jpg.pathExtension, "jpg")
        let decoded = try XCTUnwrap(ImageLoader.cgImage(at: jpg, maxPixelSize: 400))
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 240)

        // Filename suffix is applied.
        let suffixed = try exporter.export(photo, to: dir,
            settings: ExportSettings(format: .jpeg, maxPixelSize: 100, fileNameSuffix: "_web"))
        XCTAssertTrue(suffixed.deletingPathExtension().lastPathComponent.hasSuffix("_web"))
    }

    func testExportPreservesSourceMetadata() throws {
        // Build a source JPEG carrying TIFF/EXIF metadata.
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: src) }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: cs,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let img = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(src as CFURL, "public.jpeg" as CFString, 1, nil))
        let meta: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam Inc."],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifISOSpeedRatings: [640]]
        ]
        CGImageDestinationAddImage(dest, img, meta as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        // Import into a fresh library, export rendered, read metadata back.
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-meta-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)

        let lib = try ApertureLibrary(url: libURL)
        let photo = try XCTUnwrap(try lib.photos().first)
        let outDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: outDir) }
        let out = try Exporter(library: lib).export(photo, to: outDir,
            settings: ExportSettings(format: .jpeg, maxPixelSize: 0))

        let osrc = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(osrc, 0, nil) as? [CFString: Any])
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake] as? String, "TestCam Inc.")
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
