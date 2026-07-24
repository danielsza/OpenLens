import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class ReferencedVaultTests: XCTestCase {

    private func makePNG(_ url: URL) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 22, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 22, height: 16))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testReferencedImportKeepsFileInPlace() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-ref-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)

        // Source lives in its own folder, outside the library.
        let srcDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("refsrc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: srcDir) }
        let src = srcDir.appendingPathComponent("keepme.png")
        try makePNG(src)

        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let v = try writer.importImage(at: src, intoProject: project, referenced: true)

        // File was NOT copied into the library.
        let mastersContents = (try? FileManager.default
            .subpathsOfDirectory(atPath: libURL.appendingPathComponent("Masters").path)) ?? []
        XCTAssertFalse(mastersContents.contains { $0.hasSuffix("keepme.png") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))

        // Reader resolves it in place, flags it referenced, and it displays.
        let lib = try ApertureLibrary(url: libURL)
        let photo = try XCTUnwrap(try lib.photos().first { $0.id == v })
        XCTAssertTrue(photo.master.isReference)
        XCTAssertEqual(lib.masterFileURL(for: photo.master), src)
        XCTAssertTrue(ImageLoader.canDecode(lib.displayImageURL(for: photo)))
        XCTAssertTrue(try lib.checkConsistency().isHealthy)

        // Deleting the original is detected by the checker.
        try FileManager.default.removeItem(at: src)
        let report = try ApertureLibrary(url: libURL).checkConsistency()
        XCTAssertTrue(report.issues.contains {
            if case .missingMasterFile = $0 { return true }; return false
        })
    }

    func testVaultBackupCopiesAndVerifies() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-vault-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)

        let vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaults-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultDir) }

        let lib = try ApertureLibrary(url: libURL)
        let (vaultURL, report) = try lib.createVault(in: vaultDir)
        XCTAssertTrue(report.isHealthy)
        XCTAssertTrue(vaultURL.lastPathComponent.contains("-vault-"))
        let copy = try ApertureLibrary(url: vaultURL)
        XCTAssertEqual(try copy.photos().count, try lib.photos().count)
    }
}
