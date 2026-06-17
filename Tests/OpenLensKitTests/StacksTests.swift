import XCTest
@testable import OpenLensKit

final class StacksTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run stack tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testReadsStacks() throws {
        let lib = try openTestLibrary()
        let stacks = try lib.stacks()
        // Members must be valid version uuids and the pick (if any) a member.
        let validIDs = Set(try lib.versions(includeHidden: true).map { $0.id })
        for stack in stacks {
            XCTAssertFalse(stack.versionUuids.isEmpty)
            for v in stack.versionUuids { XCTAssertTrue(validIDs.contains(v)) }
            if let pick = stack.pickVersionUuid {
                XCTAssertTrue(stack.versionUuids.contains(pick))
            }
        }
    }

    func testPhotosInStackAreOrdered() throws {
        let lib = try openTestLibrary()
        guard let stack = try lib.stacks().first else {
            throw XCTSkip("No stacks in this library")
        }
        let photos = try lib.photos(inStack: stack)
        XCTAssertEqual(photos.map { $0.id },
                       stack.versionUuids.filter { id in
                           (try? lib.photos())?.contains { $0.id == id } ?? false
                       })
    }

    func testVersionsCarryStackUuid() throws {
        let lib = try openTestLibrary()
        let versions = try lib.versions()
        // If the library has stacks, at least one version references one.
        if !(try lib.stacks().isEmpty) {
            XCTAssertTrue(versions.contains { $0.stackUuid != nil })
        }
    }
}
