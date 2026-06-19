import XCTest
@testable import OpenLensKit

/// Metadata / thumbnail reading, run against a real library when
/// OPENLENS_TEST_LIBRARY is set (skipped otherwise).
final class MetadataTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run metadata tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testFindsVersionPlist() throws {
        let lib = try openTestLibrary()
        let photo = try XCTUnwrap(try lib.photos().first)
        XCTAssertNotNil(lib.versionPlistURL(for: photo))
    }

    func testParsesMetadata() throws {
        let lib = try openTestLibrary()
        for photo in try lib.photos() {
            let meta = try XCTUnwrap(lib.metadata(for: photo))
            // Every photo in a camera-sourced library should have dimensions.
            if let w = meta.pixelWidth { XCTAssertGreaterThan(w, 0) }
        }
    }

    func testResolvesThumbnailOrFallsBack() throws {
        let lib = try openTestLibrary()
        let fm = FileManager.default
        for photo in try lib.photos() {
            // displayImageURL must always point at an existing file (thumbnail
            // when available, otherwise the master).
            let url = lib.displayImageURL(for: photo)
            XCTAssertTrue(fm.fileExists(atPath: url.path), "No display image for \(photo.version.name)")
        }
    }

    func testReadsGPSFromVersion() throws {
        let lib = try openTestLibrary()
        // Fixture: pic1 is geotagged (Toronto ~43.65, -79.38); pic2 is not.
        let photos = try lib.photos()
        let located = photos.first { $0.version.hasLocation }
        let geo = try XCTUnwrap(located)
        XCTAssertEqual(geo.version.latitude ?? 0, 43.6532, accuracy: 0.01)
        XCTAssertEqual(geo.version.longitude ?? 0, -79.3832, accuracy: 0.01)
        XCTAssertTrue(photos.contains { !$0.version.hasLocation })
    }

    func testApexApertureConversion() {
        // APEX ApertureValue 6 -> f/8 ; 2 -> f/2.
        var dict: [String: Any] = ["exifProperties": ["ApertureValue": 6.0]]
        var m = ApertureLibrary.parseMetadata(dict)
        XCTAssertEqual(m.fNumber ?? 0, 8.0, accuracy: 0.1)
        dict = ["exifProperties": ["ApertureValue": 2.0]]
        m = ApertureLibrary.parseMetadata(dict)
        XCTAssertEqual(m.fNumber ?? 0, 2.0, accuracy: 0.1)
    }

    func testShutterFormatting() {
        XCTAssertEqual(VersionMetadata.formatShutter(0.002), "1/500s")
        XCTAssertEqual(VersionMetadata.formatShutter(2), "2s")
    }
}
