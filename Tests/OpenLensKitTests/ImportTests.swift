import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

/// Importing a photo into a freshly created library. Generates its own source
/// image, so no external library is needed.
final class ImportTests: XCTestCase {

    private func makePNG(_ url: URL, width: Int, height: Int) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("Could not create CGContext")
        }
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("Could not create image destination")
        }
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testImportImageIntoProject() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-import-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }

        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "Imports")
        let projectUuid = try XCTUnwrap(created.projects().first?.id)

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: source) }
        try makePNG(source, width: 80, height: 60)

        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let versionUuid = try writer.importImage(at: source, intoProject: projectUuid)

        let lib = try ApertureLibrary(url: libURL)
        let photos = try lib.photos()
        XCTAssertEqual(photos.count, 1)
        let photo = try XCTUnwrap(photos.first)
        XCTAssertEqual(photo.version.id, versionUuid)
        XCTAssertEqual(photo.version.projectUuid, projectUuid)
        XCTAssertEqual(photo.version.masterWidth, 80)
        XCTAssertEqual(photo.version.masterHeight, 60)

        // The master file was copied in and is decodable.
        let masterURL = lib.masterFileURL(for: photo.master)
        XCTAssertTrue(FileManager.default.fileExists(atPath: masterURL.path))
        XCTAssertTrue(ImageLoader.canDecode(lib.displayImageURL(for: photo)))

        // A thumbnail and a Version-1.apversion plist were generated on import.
        XCTAssertNotNil(lib.thumbnailURL(for: photo), "Import should generate a thumbnail")
        let meta = try XCTUnwrap(lib.metadata(for: photo))
        XCTAssertEqual(meta.pixelWidth, 80)
        XCTAssertEqual(meta.pixelHeight, 60)
    }

    func testDuplicateVersion() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-dup-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let projectUuid = try XCTUnwrap(created.projects().first?.id)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("dup-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: source) }
        try makePNG(source, width: 40, height: 30)

        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let original = try writer.importImage(at: source, intoProject: projectUuid)
        let dup = try writer.duplicateVersion(original)
        XCTAssertNotEqual(dup, original)

        let lib = try ApertureLibrary(url: libURL)
        let photos = try lib.photos()
        XCTAssertEqual(photos.count, 2)                       // both versions browse
        let masters = Set(photos.map { $0.master.id })
        XCTAssertEqual(masters.count, 1)                      // sharing one master
    }

    func testImportRequiresOptIn() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-import-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let projectUuid = try XCTUnwrap(created.projects().first?.id)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: source) }
        try makePNG(source, width: 10, height: 10)

        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: false)
        XCTAssertThrowsError(try writer.importImage(at: source, intoProject: projectUuid))
    }
}
