import XCTest
@testable import OpenLensKit

/// Opening libraries whose schema is missing optional tables must not crash —
/// real libraries vary across Aperture versions.
final class ResilienceTests: XCTestCase {

    func testMissingOptionalTablesDegradeGracefully() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-resil-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ApertureLibraryCreator.createLibrary(at: url, firstProjectNamed: "P")

        // Drop the optional tables a different Aperture build might not have.
        let dbPath = url.appendingPathComponent("Database/apdb/Library.apdb").path
        let db = try SQLiteDatabase(path: dbPath, readOnly: false)
        for t in ["RKStackContent", "RKStackState", "RKImageAdjustment",
                  "RKAlbum", "RKAlbumVersion", "RKKeyword", "RKKeywordForVersion"] {
            try db.execute("DROP TABLE IF EXISTS \(t)")
        }

        // Core reads still work; optional reads return empty instead of throwing.
        let lib = try ApertureLibrary(url: url)
        XCTAssertEqual(try lib.projects().count, 1)
        XCTAssertEqual(try lib.stacks().count, 0)
        XCTAssertEqual(try lib.albums().count, 0)
        XCTAssertEqual(try lib.userAlbums().count, 0)
        XCTAssertEqual(try lib.keywordVocabulary().count, 0)
        XCTAssertNoThrow(try lib.photos())
    }
}
