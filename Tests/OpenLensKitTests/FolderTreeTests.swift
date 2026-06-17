import XCTest
@testable import OpenLensKit

final class FolderTreeTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run folder-tree tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testHierarchyHasRootAndNoCycles() throws {
        let lib = try openTestLibrary()
        let roots = try lib.folderHierarchy()
        XCTAssertFalse(roots.isEmpty)
        // Count nodes; must equal the number of folders (a proper forest).
        func count(_ nodes: [FolderNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + count($1.children) }
        }
        XCTAssertEqual(count(roots), try lib.folders().count)
    }

    func testProjectNavigatorContainsProjects() throws {
        let lib = try openTestLibrary()
        let nav = try lib.projectNavigator()
        let projectIDs = Set(try lib.projects().map { $0.id })
        // Every project should be reachable in the navigator subtree.
        func collect(_ nodes: [FolderNode]) -> Set<String> {
            var ids: Set<String> = []
            for n in nodes where n.isProject { ids.insert(n.id) }
            for n in nodes { ids.formUnion(collect(n.children)) }
            return ids
        }
        XCTAssertTrue(projectIDs.isSubset(of: collect(nav)))
    }
}
