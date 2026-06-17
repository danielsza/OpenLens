import XCTest
@testable import OpenLensKit

final class PhotoFilterTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run filter tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testEmptyFilterKeepsEverything() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        XCTAssertEqual(PhotoFilter().apply(to: photos).count, photos.count)
    }

    func testMinRatingFilter() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        let highly = PhotoFilter(minRating: 5).apply(to: photos)
        XCTAssertTrue(highly.allSatisfy { $0.version.rating >= 5 })
        // Fixture has exactly one 5-star photo.
        XCTAssertEqual(highly.count, photos.filter { $0.version.rating >= 5 }.count)
    }

    func testFlaggedFilter() throws {
        let lib = try openTestLibrary()
        let flagged = PhotoFilter(flaggedOnly: true).apply(to: try lib.photos())
        XCTAssertTrue(flagged.allSatisfy { $0.version.isFlagged })
    }

    func testNameContainsIsCaseInsensitive() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        guard let sample = photos.first else { return }
        let needle = String(sample.version.name.prefix(3)).lowercased()
        let result = PhotoFilter(nameContains: needle).apply(to: photos)
        XCTAssertTrue(result.contains { $0.id == sample.id })
    }
}
