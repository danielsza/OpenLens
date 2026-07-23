import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class FolderImportTests: XCTestCase {

    private func makePNG(_ url: URL, shade: CGFloat) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 20, height: 15, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: shade, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 15))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testImportsTreeAsProjects() throws {
        // Build: root/Trip A (2 images), root/Trip A/Day 2 (1), root/Notes (0, skipped)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tree-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let tripA = root.appendingPathComponent("Trip A")
        let day2 = tripA.appendingPathComponent("Day 2")
        let notes = root.appendingPathComponent("Notes")
        try fm.createDirectory(at: day2, withIntermediateDirectories: true)
        try fm.createDirectory(at: notes, withIntermediateDirectories: true)
        try makePNG(tripA.appendingPathComponent("a1.png"), shade: 0.1)
        try makePNG(tripA.appendingPathComponent("a2.png"), shade: 0.2)
        try makePNG(day2.appendingPathComponent("d1.png"), shade: 0.3)
        try "not an image".write(to: notes.appendingPathComponent("readme.txt"),
                                 atomically: true, encoding: .utf8)

        let libURL = fm.temporaryDirectory
            .appendingPathComponent("OpenLens-tree-\(UUID().uuidString).aplibrary")
        defer { try? fm.removeItem(at: libURL) }
        _ = try ApertureLibraryCreator.createLibrary(at: libURL)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)

        let result = try writer.importFolderTree(at: root)
        XCTAssertEqual(result.projectsCreated, 2)     // Trip A, Day 2 (Notes has no images)
        XCTAssertEqual(result.photosImported, 3)
        XCTAssertEqual(result.skipped, 0)

        let lib = try ApertureLibrary(url: libURL)
        let names = Set(try lib.projects().map { $0.name })
        XCTAssertEqual(names, ["Trip A", "Day 2"])
        XCTAssertEqual(try lib.photos().count, 3)
        let tripAProject = try XCTUnwrap(lib.projects().first { $0.name == "Trip A" })
        XCTAssertEqual(try lib.photos(inProject: tripAProject.id).count, 2)
    }
}
