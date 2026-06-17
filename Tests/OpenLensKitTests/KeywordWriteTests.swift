import XCTest
@testable import OpenLensKit

/// Keyword write tests, always on a throwaway copy of the library.
final class KeywordWriteTests: XCTestCase {

    private func copyOfTestLibrary() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run keyword write tests.")
        }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("openlens-kw-\(UUID().uuidString).aplibrary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dst)
        return dst
    }

    func testAddCreatesAndAssignsKeyword() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)

        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)
        try writer.addKeyword("Sunset", toVersion: photo.version.id)
        // Idempotent.
        try writer.addKeyword("Sunset", toVersion: photo.version.id)

        let after = try ApertureLibrary(url: lib)
        let updated = try XCTUnwrap(after.photos().first { $0.id == photo.id })
        let kws = try after.keywords(for: updated)
        XCTAssertTrue(kws.contains("Sunset"))
        XCTAssertEqual(kws.filter { $0 == "Sunset" }.count, 1)
        XCTAssertTrue(updated.version.hasKeywords)
    }

    func testRemoveKeyword() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)

        try writer.addKeyword("Temp", toVersion: photo.version.id)
        try writer.removeKeyword("Temp", fromVersion: photo.version.id)

        let after = try ApertureLibrary(url: lib)
        let updated = try XCTUnwrap(after.photos().first { $0.id == photo.id })
        XCTAssertFalse(try after.keywords(for: updated).contains("Temp"))
    }

    func testSetKeywordsReplaces() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)

        try writer.setKeywords(["Alpha", "Beta"], forVersion: photo.version.id)
        let after = try ApertureLibrary(url: lib)
        let updated = try XCTUnwrap(after.photos().first { $0.id == photo.id })
        XCTAssertEqual(Set(try after.keywords(for: updated)), ["Alpha", "Beta"])
    }
}
