import XCTest
@testable import OpenLensKit

/// Write tests. These ALWAYS operate on a throwaway copy of the library so the
/// fixture (and any real OPENLENS_TEST_LIBRARY) is never mutated. Run when
/// OPENLENS_TEST_LIBRARY is set, otherwise skipped.
final class WriterTests: XCTestCase {

    /// Copies the test library to a unique temp dir and returns its URL.
    private func copyOfTestLibrary() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run writer tests.")
        }
        let src = URL(fileURLWithPath: path)
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("openlens-write-\(UUID().uuidString).aplibrary")
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    func testWritesAreRefusedWhenNotAllowed() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: false)
        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)
        XCTAssertThrowsError(try writer.setRating(3, forVersion: photo.version.id))
    }

    func testSetRatingUpdatesDatabaseAndPlist() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }

        // Read a starting photo and pick a new rating different from current.
        let before = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try before.photos().first)
        let newRating = photo.version.rating == 4 ? 2 : 4

        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)
        try writer.setRating(newRating, forVersion: photo.version.id)

        // The catalog reflects the new rating.
        let after = try ApertureLibrary(url: lib)
        let updated = try XCTUnwrap(after.photos().first { $0.id == photo.id })
        XCTAssertEqual(updated.version.rating, newRating)

        // The .apversion plist reflects it too (DB + plist kept in sync).
        let plistURL = try XCTUnwrap(after.versionPlistURL(for: updated))
        let dict = try XCTUnwrap(ApertureLibrary.readPlist(plistURL))
        XCTAssertEqual((dict["mainRating"] as? NSNumber)?.intValue, newRating)
        let iptc = dict["iptcProperties"] as? [String: Any]
        XCTAssertEqual(iptc?["StarRating"] as? String, String(newRating))
    }

    func testSetFlagAndColorLabel() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }

        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)

        let newFlag = !photo.version.isFlagged
        try writer.setFlagged(newFlag, forVersion: photo.version.id)
        try writer.setColorLabel(ColorLabel.green.rawValue, forVersion: photo.version.id)

        let after = try ApertureLibrary(url: lib)
        let updated = try XCTUnwrap(after.photos().first { $0.id == photo.id })
        XCTAssertEqual(updated.version.isFlagged, newFlag)
        XCTAssertEqual(updated.version.colorLabel, ColorLabel.green.rawValue)
    }

    func testBackupCatalogCreatesCopy() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)
        let backup = try writer.backupCatalog()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertGreaterThan((try Data(contentsOf: backup)).count, 0)
    }
}
