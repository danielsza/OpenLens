import XCTest
@testable import OpenLensKit

final class SearchTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run search tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testSearchByKeyword() throws {
        let lib = try openTestLibrary()
        // Fixture: pic1 has the keyword "Beach".
        let hits = try lib.search("beach")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(try lib.keywords(for: hits[0]).contains("Beach"))
    }

    func testSearchByCameraMatchesAll() throws {
        let lib = try openTestLibrary()
        // Both fixture photos are shot on a Canon.
        let hits = try lib.search("canon")
        XCTAssertEqual(hits.count, try lib.photos().count)
    }

    func testEmptyQueryReturnsAll() throws {
        let lib = try openTestLibrary()
        XCTAssertEqual(try lib.search("   ").count, try lib.photos().count)
    }

    func testAllTermsMustMatch() throws {
        let lib = try openTestLibrary()
        // "canon" matches all; "beach" only pic1 -> AND gives 1.
        XCTAssertEqual(try lib.search("canon beach").count, 1)
        // A term that matches nothing yields no results.
        XCTAssertEqual(try lib.search("canon zzzznope").count, 0)
    }
}
