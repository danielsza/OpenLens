import SwiftUI
import OpenLensKit

struct ProjectSidebar: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        List {
            Section("Library") {
                ForEach(LibraryStore.LibrarySource.allCases) { source in
                    row(title: source.rawValue,
                        systemImage: source.systemImage,
                        count: count(for: source),
                        isSelected: store.selectedSource == source) {
                        store.selectSource(source)
                    }
                }
            }

            Section("Projects") {
                if store.projectTree.isEmpty {
                    ForEach(store.projects) { project in
                        projectRow(project)
                    }
                } else {
                    OutlineGroup(store.projectTree, children: \.nonEmptyChildren) { node in
                        if node.isProject {
                            projectRow(node.folder)
                        } else {
                            Label(node.name.isEmpty ? "Folder" : node.name, systemImage: "folder")
                        }
                    }
                }
            }

            if !store.userAlbums.isEmpty {
                Section("Albums") {
                    ForEach(store.userAlbums) { album in
                        row(title: album.displayName,
                            systemImage: "photo.stack",
                            count: nil,
                            isSelected: store.selectedAlbumID == album.id) {
                            store.selectAlbum(album.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
    }

    private func count(for source: LibraryStore.LibrarySource) -> Int {
        switch source {
        case .allPhotos: return store.photos.count
        case .flagged: return store.photos.filter { $0.version.isFlagged }.count
        case .rejected: return store.photos.filter { $0.version.rating < 0 }.count
        case .trash: return store.trashed.count
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        row(title: project.name.isEmpty ? "Untitled" : project.name,
            systemImage: "rectangle.stack",
            count: store.photos.filter { $0.version.projectUuid == project.id }.count,
            isSelected: store.selectedProjectID == project.id) {
            store.selectProject(project.id)
        }
    }

    @ViewBuilder
    private func row(title: String, systemImage: String, count: Int?,
                     isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                Spacer()
                if let count { Text("\(count)").foregroundStyle(.secondary).font(.caption) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}
