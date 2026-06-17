import XCTest
@testable import OpenLensKit

/// These tests run against a real Aperture library. Point them at one with:
///
///   OPENLENS_TEST_LIBRARY=/path/to/test.aplibrary swift test
///
/// If the variable is unset the tests are skipped, so CI and contributors
/// without a library still get a green build.
final class ApertureLibraryTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run reader tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testOpensLibrary() throws {
        let lib = try openTestLibrary()
        XCTAssertFalse(lib.version.isEmpty)
    }

    func testReadsProjects() throws {
        let lib = try openTestLibrary()
        let projects = try lib.projects()
        XCTAssertFalse(projects.isEmpty, "Expected at least one project")
        for p in projects {
            XCTAssertEqual(p.folderType, 2)
            XCTAssertFalse(p.id.isEmpty)
        }
    }

    func testReadsPhotosJoinedToMasters() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        XCTAssertFalse(photos.isEmpty, "Expected at least one photo")
        for photo in photos {
            XCTAssertEqual(photo.version.masterUuid, photo.master.id)
            XCTAssertFalse(photo.master.imagePath.isEmpty)
            XCTAssertTrue((0...5).contains(photo.version.rating))
        }
    }

    func testMasterFilesResolveOnDisk() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        let fm = FileManager.default
        for photo in photos where !photo.master.isReference {
            let url = lib.masterFileURL(for: photo.master)
            XCTAssertTrue(fm.fileExists(atPath: url.path),
                          "Master file missing: \(url.path)")
        }
    }

    func testAppleDateConversion() {
        // 2001-01-01 00:00:00 UTC is reference-date 0.
        let date = ApertureLibrary.appleDate(0)
        XCTAssertEqual(date?.timeIntervalSince1970, 978307200, accuracy: 1)
    }
}
