import XCTest
@testable import OpenLensKit

/// Creating projects and albums in a freshly created library.
final class StructureWriteTests: XCTestCase {

    private func newLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-struct-\(UUID().uuidString).aplibrary")
        _ = try ApertureLibraryCreator.createLibrary(at: url)
        return url
    }

    func testCreateProject() throws {
        let url = try newLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: true)
        let uuid = try writer.createProject(named: "Iceland")

        let lib = try ApertureLibrary(url: url)
        let projects = try lib.projects()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.id, uuid)
        XCTAssertEqual(projects.first?.name, "Iceland")
        // Appears in the project navigator subtree.
        let navIDs = try lib.projectNavigator().map { $0.id }
        XCTAssertTrue(navIDs.contains(uuid))
    }

    func testCreateAlbum() throws {
        let url = try newLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: true)
        let uuid = try writer.createAlbum(named: "Portfolio")

        let lib = try ApertureLibrary(url: url)
        let userAlbums = try lib.userAlbums()
        XCTAssertTrue(userAlbums.contains { $0.id == uuid && $0.name == "Portfolio" })
    }

    func testRenameProjectAndAlbum() throws {
        let url = try newLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: true)
        let proj = try writer.createProject(named: "Old")
        let album = try writer.createAlbum(named: "OldAlbum")
        try writer.renameProject(proj, to: "New Trip")
        try writer.renameAlbum(album, to: "Best Of")

        let lib = try ApertureLibrary(url: url)
        XCTAssertEqual(try lib.projects().first { $0.id == proj }?.name, "New Trip")
        XCTAssertTrue(try lib.userAlbums().contains { $0.id == album && $0.name == "Best Of" })
    }

    func testStructureWritesRequireOptIn() throws {
        let url = try newLibrary()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = ApertureLibraryWriter(libraryURL: url, allowWrites: false)
        XCTAssertThrowsError(try writer.createProject(named: "X"))
        XCTAssertThrowsError(try writer.createAlbum(named: "Y"))
    }
}
