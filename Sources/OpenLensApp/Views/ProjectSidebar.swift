import SwiftUI
import OpenLensKit

struct ProjectSidebar: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        List(selection: $store.selectedProjectID) {
            Section("Projects") {
                ForEach(store.projects) { project in
                    Label {
                        HStack {
                            Text(project.name.isEmpty ? "Untitled" : project.name)
                            Spacer()
                            Text("\(count(for: project))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "rectangle.stack")
                    }
                    .tag(project.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(for project: Project) -> Int {
        store.photos.filter { $0.version.projectUuid == project.id }.count
    }
}
