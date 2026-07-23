import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class ConsistencyTests: XCTestCase {

    private func makePNG(_ url: URL, _ w: Int, _ h: Int) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testHealthyLibraryPassesAndDamageIsDetected() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-cons-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src, 32, 24)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)

        // Fresh import: healthy.
        var lib = try ApertureLibrary(url: libURL)
        var report = try lib.checkConsistency()
        XCTAssertTrue(report.isHealthy, "unexpected issues: \(report.issues)")
        XCTAssertEqual(report.photosChecked, 1)

        // Damage: delete the master file.
        let photo = try XCTUnwrap(try lib.photos().first)
        try FileManager.default.removeItem(at: lib.masterFileURL(for: photo.master))
        lib = try ApertureLibrary(url: libURL)
        report = try lib.checkConsistency()
        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.issues.contains {
            if case .missingMasterFile = $0 { return true }; return false
        })
    }

    func testRepairFixesDanglingRowsAndMissingThumbnail() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-repair-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("r-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src, 32, 24)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)

        // Damage: dangling album/keyword rows + delete the generated thumbnail.
        let db = try SQLiteDatabase(path: libURL.appendingPathComponent("Database/apdb/Library.apdb").path,
                                    readOnly: false)
        try db.execute("INSERT INTO RKAlbumVersion(modelId, versionId, albumId) VALUES (999, 424242, 1)")
        try db.execute("INSERT INTO RKKeywordForVersion(modelId, versionId, keywordId) VALUES (999, 424242, 1)")
        let thumbs = libURL.appendingPathComponent("Thumbnails")
        if let e = FileManager.default.enumerator(at: thumbs, includingPropertiesForKeys: nil) {
            for case let f as URL in e where f.pathExtension == "jpg" {
                try FileManager.default.removeItem(at: f)
            }
        }

        var lib = try ApertureLibrary(url: libURL)
        let before = try lib.checkConsistency()
        XCTAssertFalse(before.isHealthy)

        let fixed = try writer.repair(before, in: lib)
        XCTAssertGreaterThanOrEqual(fixed, 3)

        lib = try ApertureLibrary(url: libURL)
        let after = try lib.checkConsistency()
        XCTAssertTrue(after.isHealthy, "remaining: \(after.issues)")
    }

    func testFixtureIsHealthy() throws {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY")
        }
        let lib = try ApertureLibrary(url: URL(fileURLWithPath: path))
        let report = try lib.checkConsistency()
        XCTAssertTrue(report.isHealthy, "fixture issues: \(report.issues)")
    }
}
