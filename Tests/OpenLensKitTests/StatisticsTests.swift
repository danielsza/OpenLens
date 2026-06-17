import XCTest
@testable import OpenLensKit

final class StatisticsTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run statistics tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testStatisticsMatchFixture() throws {
        let lib = try openTestLibrary()
        let s = try lib.statistics()
        XCTAssertEqual(s.projectCount, 1)
        XCTAssertEqual(s.photoCount, 2)
        XCTAssertEqual(s.masterCount, 2)
        XCTAssertEqual(s.albumCount, 1)            // "Favorites"
        XCTAssertEqual(s.stackCount, 1)
        XCTAssertEqual(s.flaggedCount, 1)
        XCTAssertEqual(s.editedCount, 1)
        XCTAssertEqual(s.ratingHistogram[5], 1)
        XCTAssertEqual(s.ratingHistogram[0], 1)
        // Histogram totals must equal the photo count.
        XCTAssertEqual(s.ratingHistogram.values.reduce(0, +), s.photoCount)
    }

    func testStatisticsAreConsistentForAnyLibrary() throws {
        let lib = try openTestLibrary()
        let s = try lib.statistics()
        XCTAssertEqual(s.ratingHistogram.values.reduce(0, +), s.photoCount)
        XCTAssertLessThanOrEqual(s.flaggedCount, s.photoCount)
        XCTAssertLessThanOrEqual(s.referencedMasterCount, s.masterCount)
    }
}
