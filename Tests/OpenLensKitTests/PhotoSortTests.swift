import XCTest
@testable import OpenLensKit

final class PhotoSortTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run sort tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testSortByNameAscending() throws {
        let photos = try openTestLibrary().photos()
        let names = photos.sorted(by: .name).map { $0.version.name }
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testSortByRatingDescendingPutsHighestFirst() throws {
        let photos = try openTestLibrary().photos()
        let sorted = photos.sorted(by: .rating, ascending: false)
        // Fixture: pic1 is 5★, pic2 is 0★.
        XCTAssertEqual(sorted.first?.version.rating, photos.map { $0.version.rating }.max())
    }

    func testSortPreservesCount() throws {
        let photos = try openTestLibrary().photos()
        for s in PhotoSort.allCases {
            XCTAssertEqual(photos.sorted(by: s).count, photos.count)
        }
    }
}
