import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

/// Stack create/break/pick and move/delete, on a created library with imported
/// photos. Self-contained (generates its own images).
final class StackWriteTests: XCTestCase {

    private func makePNG(_ url: URL, _ w: Int, _ h: Int) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    private func libWithTwoPhotos() throws -> (URL, ApertureLibraryWriter, String, [Photo]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-stk-\(UUID().uuidString).aplibrary")
        let created = try ApertureLibraryCreator.createLibrary(at: url, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: true)
        for i in 0..<2 {
            let src = FileManager.default.temporaryDirectory.appendingPathComponent("s\(i)-\(UUID().uuidString).png")
            try makePNG(src, 30, 20)
            _ = try writer.importImage(at: src, intoProject: project)
            try? FileManager.default.removeItem(at: src)
        }
        let photos = try ApertureLibrary(url: url).photos()
        return (url, writer, project, photos)
    }

    func testCreateAndBreakStack() throws {
        let (url, writer, _, photos) = try libWithTwoPhotos()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(photos.count, 2)

        let stackId = try writer.createStack(versionUuids: photos.map { $0.id }, pick: photos[1].id)
        var lib = try ApertureLibrary(url: url)
        let stacks = try lib.stacks()
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?.versionUuids.count, 2)
        XCTAssertEqual(stacks.first?.pickVersionUuid, photos[1].id)

        try writer.breakStack(stackId)
        lib = try ApertureLibrary(url: url)
        XCTAssertTrue(try lib.stacks().isEmpty)
        XCTAssertTrue(try lib.photos().allSatisfy { $0.version.stackUuid == nil })
    }

    func testDeleteAlbumAndMoveVersion() throws {
        let (url, writer, _, photos) = try libWithTwoPhotos()
        defer { try? FileManager.default.removeItem(at: url) }

        let album = try writer.createAlbum(named: "Temp")
        try writer.addVersion(photos[0].id, toAlbumUuid: album)
        try writer.deleteAlbum(album)
        XCTAssertTrue(try ApertureLibrary(url: url).userAlbums().isEmpty)

        let other = try writer.createProject(named: "Other")
        try writer.moveVersion(photos[0].id, toProject: other)
        let moved = try ApertureLibrary(url: url).photos(inProject: other)
        XCTAssertTrue(moved.contains { $0.id == photos[0].id })
    }
}
