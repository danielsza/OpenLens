import XCTest
@testable import OpenLensKit

/// Albums + keywords, run against a real library when OPENLENS_TEST_LIBRARY is
/// set (skipped otherwise).
final class AlbumsKeywordsTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run album/keyword tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testReadsAlbums() throws {
        let lib = try openTestLibrary()
        let all = try lib.albums()
        XCTAssertFalse(all.isEmpty, "Every library has system albums")
        // System albums must be classified as system.
        XCTAssertTrue(all.contains { $0.name == "flaggedAlbum" && $0.isSystem })
        // userAlbums must exclude all system albums.
        for a in try lib.userAlbums() {
            XCTAssertFalse(a.isSystem)
        }
    }

    func testReadsKeywordVocabulary() throws {
        let lib = try openTestLibrary()
        let vocab = try lib.keywordVocabulary()
        // Tree integrity: any parentModelId must reference an existing keyword.
        let ids = Set(vocab.map { $0.modelId })
        for kw in vocab {
            if let parent = kw.parentModelId {
                XCTAssertTrue(ids.contains(parent), "Dangling parent for \(kw.name)")
            }
        }
    }

    func testPhotosInAlbumAreSubset() throws {
        let lib = try openTestLibrary()
        let allIDs = Set(try lib.photos().map { $0.id })
        for album in try lib.userAlbums() {
            for photo in try lib.photos(inAlbum: album) {
                XCTAssertTrue(allIDs.contains(photo.id))
            }
        }
    }
}
