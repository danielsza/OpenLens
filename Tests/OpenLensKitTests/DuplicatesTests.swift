import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class DuplicatesTests: XCTestCase {

    private func makePNG(_ url: URL, shade: CGFloat) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 24, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: shade, green: shade, blue: shade, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testFindsByteIdenticalDuplicatesOnly() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-dupdet-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)

        let a = FileManager.default.temporaryDirectory.appendingPathComponent("dupA-\(UUID().uuidString).png")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("dupB-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try makePNG(a, shade: 0.5)
        try FileManager.default.copyItem(at: a, to: b)     // byte-identical copy
        let c = FileManager.default.temporaryDirectory.appendingPathComponent("uniq-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: c) }
        try makePNG(c, shade: 0.9)                         // different content

        _ = try writer.importImage(at: a, intoProject: project)
        _ = try writer.importImage(at: b, intoProject: project)
        let uniqueVersion = try writer.importImage(at: c, intoProject: project)
        // Duplicate a version — must NOT count as a duplicate (same master).
        _ = try writer.duplicateVersion(uniqueVersion)

        let lib = try ApertureLibrary(url: libURL)
        let groups = try lib.findDuplicates()
        XCTAssertEqual(groups.count, 1, "expected exactly one duplicate group, got \(groups)")
        XCTAssertEqual(groups.first?.count, 2)
    }
}
