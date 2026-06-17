import SwiftUI
import AppKit
import OpenLensKit

struct ContentView: View {
    @StateObject private var store = LibraryStore()

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(store: store)
                .frame(minWidth: 200)
        } content: {
            PhotoGrid(store: store)
                .frame(minWidth: 360)
        } detail: {
            PhotoInspector(store: store)
                .frame(minWidth: 260)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    openLibrary()
                } label: {
                    Label("Open Library", systemImage: "folder")
                }
            }
            ToolbarItem(placement: .automatic) {
                Toggle("Save edits", isOn: $store.writesEnabled)
                    .help("When on, ratings and flags are written back to the library on disk.")
            }
        }
        .overlay {
            if store.library == nil {
                ContentUnavailablePlaceholder(action: openLibrary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLibraryRequested)) { _ in
            openLibrary()
        }
        .alert("Library error",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func openLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.message = "Choose an Aperture library (.aplibrary)"
        if panel.runModal() == .OK, let url = panel.url {
            store.open(url: url)
        }
    }
}

/// Simple placeholder shown before a library is opened (avoids depending on
/// ContentUnavailableView, which is macOS 14+ only).
struct ContentUnavailablePlaceholder: View {
    let action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No library open")
                .font(.title2)
            Button("Open Library…", action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
