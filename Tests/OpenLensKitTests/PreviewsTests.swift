import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class PreviewsTests: XCTestCase {

    private func makePNG(_ url: URL, _ w: Int, _ h: Int) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testPreviewResolutionAndViewerPreference() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-prev-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src, 40, 30)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)

        var lib = try ApertureLibrary(url: libURL)
        let photo = try XCTUnwrap(try lib.photos().first)

        // No preview yet: viewer falls back to the master.
        XCTAssertNil(lib.previewURL(for: photo))
        XCTAssertEqual(lib.viewerImageURL(for: photo), lib.masterFileURL(for: photo.master))

        // Create a preview at Aperture's layout; viewer should now prefer it.
        let datePath = (photo.master.imagePath as NSString).deletingLastPathComponent
        let dir = lib.previewsURL.appendingPathComponent(datePath).appendingPathComponent(photo.version.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previewFile = dir.appendingPathComponent("\(photo.version.name).jpg")
        try makePNG(previewFile, 20, 15)   // content sniffing makes this decodable

        lib = try ApertureLibrary(url: libURL)
        XCTAssertEqual(lib.previewURL(for: photo), previewFile)
        XCTAssertEqual(lib.viewerImageURL(for: photo), previewFile)
        XCTAssertTrue(ImageLoader.canDecode(previewFile))
    }
}
