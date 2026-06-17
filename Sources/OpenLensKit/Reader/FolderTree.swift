import Foundation

/// A node in the folder/project tree. Aperture nests folders and projects via
/// `RKFolder.parentFolderUuid`; this turns the flat rows into a tree the UI can
/// render with disclosure triangles.
public struct FolderNode: Identifiable, Hashable {
    public let folder: Project
    public var children: [FolderNode]
    public var id: String { folder.id }
    public var isProject: Bool { folder.isProject }
    public var name: String { folder.name }

    /// `nil` for leaves so SwiftUI's `OutlineGroup` doesn't draw an empty
    /// disclosure triangle.
    public var nonEmptyChildren: [FolderNode]? { children.isEmpty ? nil : children }
}

public extension ApertureLibrary {

    /// The full folder tree (all non-trash folders), as root nodes.
    func folderHierarchy() throws -> [FolderNode] {
        let folders = try self.folders()
        var byUuid: [String: Project] = [:]
        var childrenByParent: [String: [Project]] = [:]
        for f in folders {
            byUuid[f.id] = f
            if let parent = f.parentUuid {
                childrenByParent[parent, default: []].append(f)
            }
        }
        func build(_ f: Project) -> FolderNode {
            let kids = (childrenByParent[f.id] ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(build)
            return FolderNode(folder: f, children: kids)
        }
        let roots = folders.filter { f in
            guard let parent = f.parentUuid else { return true }
            return byUuid[parent] == nil
        }
        return roots.map(build)
    }

    /// The user-facing project navigator: the subtree under the "Projects"
    /// container (folders the user made, with their projects nested inside).
    /// Falls back to a flat list of projects if the container isn't found.
    func projectNavigator() throws -> [FolderNode] {
        let tree = try folderHierarchy()
        func findProjectsContainer(_ nodes: [FolderNode]) -> FolderNode? {
            for n in nodes {
                if n.folder.id == "AllProjectsItem" || n.folder.name == "Projects" {
                    return n
                }
                if let found = findProjectsContainer(n.children) { return found }
            }
            return nil
        }
        if let container = findProjectsContainer(tree) {
            return container.children
        }
        return try projects().map { FolderNode(folder: $0, children: []) }
    }
}
