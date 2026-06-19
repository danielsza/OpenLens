import XCTest
@testable import OpenLensKit

final class PhotoGroupingTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run grouping tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testGroupingPreservesPhotoCount() throws {
        let lib = try openTestLibrary()
        let photos = try lib.photos()
        for g in [DateGranularity.day, .month, .year] {
            let sections = photos.grouped(by: g)
            let total = sections.reduce(0) { $0 + $1.photos.count }
            XCTAssertEqual(total, photos.count)
        }
    }

    func testFixturePhotosShareOneDay() throws {
        let lib = try openTestLibrary()
        // Both fixture photos were captured 2020-07-09, so they form one day.
        let sections = try lib.photos().grouped(by: .day)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.photos.count, try lib.photos().count)
        XCTAssertNotNil(sections.first?.date)
    }

    func testSectionsAreChronological() throws {
        let lib = try openTestLibrary()
        let sections = try lib.photos().grouped(by: .day)
        let dates = sections.compactMap { $0.date }
        XCTAssertEqual(dates, dates.sorted())
    }
}
