import XCTest
@testable import OpenLensKit

/// Creating a new library writes a package OpenLens can open. No env library
/// needed — this builds and reads its own.
final class LibraryCreatorTests: XCTestCase {

    private func tempLibraryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-new-\(UUID().uuidString).aplibrary")
    }

    func testCreatesAnOpenableLibrary() throws {
        let url = tempLibraryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let lib = try ApertureLibraryCreator.createLibrary(at: url)
        XCTAssertEqual(lib.version, "3.6")
        XCTAssertTrue(try lib.projects().isEmpty)        // no project seeded
        XCTAssertTrue(try lib.photos().isEmpty)
        // System albums exist and are classified as system.
        XCTAssertTrue(try lib.albums().contains { $0.name == "flaggedAlbum" && $0.isSystem })
        XCTAssertTrue(try lib.userAlbums().isEmpty)
    }

    func testCreatesWithFirstProject() throws {
        let url = tempLibraryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let lib = try ApertureLibraryCreator.createLibrary(at: url, firstProjectNamed: "My Trip")
        let projects = try lib.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.name, "My Trip")
        XCTAssertEqual(projects.first?.folderType, 2)
    }

    func testRefusesToOverwrite() throws {
        let url = tempLibraryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ApertureLibraryCreator.createLibrary(at: url)
        XCTAssertThrowsError(try ApertureLibraryCreator.createLibrary(at: url))
    }

    func testWriterWorksOnCreatedLibrary() throws {
        // A freshly created library + a project + (manually inserted) version is
        // beyond scope here; just confirm the catalog is writable by toggling a
        // backup, proving the DB opens read-write cleanly.
        let url = tempLibraryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ApertureLibraryCreator.createLibrary(at: url)
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: true)
        XCTAssertNoThrow(try writer.backupCatalog())
    }
}
