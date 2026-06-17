import XCTest
@testable import OpenLensKit

/// Trash move/restore, always on a throwaway copy of the library.
final class TrashTests: XCTestCase {

    private func copyOfTestLibrary() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run trash tests.")
        }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("openlens-trash-\(UUID().uuidString).aplibrary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dst)
        return dst
    }

    func testMoveToTrashAndRestore() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }

        let before = try ApertureLibrary(url: lib)
        let startCount = try before.photos().count
        let photo = try XCTUnwrap(try before.photos().first)
        XCTAssertTrue(try before.trashedPhotos().isEmpty)

        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: true)
        try writer.moveToTrash(versionUuid: photo.version.id)

        let trashed = try ApertureLibrary(url: lib)
        XCTAssertEqual(try trashed.photos().count, startCount - 1)
        XCTAssertTrue(try trashed.trashedPhotos().contains { $0.id == photo.id })

        try writer.restoreFromTrash(versionUuid: photo.version.id)
        let restored = try ApertureLibrary(url: lib)
        XCTAssertEqual(try restored.photos().count, startCount)
        XCTAssertTrue(try restored.trashedPhotos().isEmpty)
    }

    func testTrashWriteRequiresOptIn() throws {
        let lib = try copyOfTestLibrary()
        defer { try? FileManager.default.removeItem(at: lib) }
        let reader = try ApertureLibrary(url: lib)
        let photo = try XCTUnwrap(try reader.photos().first)
        let writer = ApertureLibraryWriter(libraryURL: lib, allowWrites: false)
        XCTAssertThrowsError(try writer.moveToTrash(versionUuid: photo.version.id))
    }
}
