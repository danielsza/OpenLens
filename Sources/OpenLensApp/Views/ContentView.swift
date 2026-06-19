import SwiftUI
import AppKit
import OpenLensKit

struct ContentView: View {
    @StateObject private var store = LibraryStore()
    @State private var didAutoOpen = false

    var body: some View {
        HSplitView {
            LeftInspector(store: store)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            centerColumn
                .frame(minWidth: 520)
        }
        .background(Theme.appBackground)
        .toolbar { toolbarContent }
        .overlay {
            if store.library == nil {
                ContentUnavailablePlaceholder(action: openLibrary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLibraryRequested)) { _ in
            openLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newLibraryRequested)) { _ in
            newLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeLibraryRequested)) { _ in
            store.closeLibrary()
        }
        .onAppear { autoOpenIfNeeded() }
        .alert("Library error",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Center column

    private var centerColumn: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().overlay(Theme.hairline)
            content
            Divider().overlay(Theme.hairline)
            ControlBar(store: store)
        }
        .background(Theme.appBackground)
        .background(keyboardShortcuts)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left, .up: store.selectOffset(-1)
            case .right, .down: store.selectOffset(1)
            default: break
            }
        }
    }

    /// Hidden buttons providing Aperture-style keyboard shortcuts: 1–5 rate,
    /// 0 clears, "/" toggles flag.
    private var keyboardShortcuts: some View {
        Group {
            ForEach(0...5, id: \.self) { n in
                Button("") {
                    if let p = store.selectedPhoto { store.setRating(n, for: p) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [])
            }
            Button("") {
                if let p = store.selectedPhoto { store.toggleFlag(for: p) }
            }
            .keyboardShortcut("/", modifiers: [])
            // 9 = Reject (rating -1), as in Aperture.
            Button("") {
                if let p = store.selectedPhoto { store.setRating(-1, for: p) }
            }
            .keyboardShortcut("9", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    @ViewBuilder
    private var content: some View {
        switch store.viewMode {
        case .grid:
            GridBrowser(store: store)
        case .split:
            VSplitView {
                ImageViewer(store: store).frame(minHeight: 200)
                Filmstrip(store: store).frame(height: 150)
            }
        case .viewer:
            ImageViewer(store: store)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Rating", selection: $store.filter.minRating) {
                Text("All").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)★+").tag($0) }
            }
            .pickerStyle(.menu).frame(width: 110)

            Toggle("Flagged", isOn: $store.filter.flaggedOnly).toggleStyle(.button)
            Toggle("Edited", isOn: $store.filter.adjustedOnly).toggleStyle(.button)

            TextField("Filter by name", text: $store.filter.nameContains)
                .textFieldStyle(.roundedBorder).frame(width: 160)

            Spacer()
            Text(statusText)
                .foregroundStyle(Theme.textSecondary).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.panel)
    }

    private var statusText: String {
        let photos = store.visiblePhotos
        if let id = store.selectedPhotoID,
           let idx = photos.firstIndex(where: { $0.id == id }) {
            return "\(idx + 1) of \(photos.count) — \(photos.count) displayed"
        }
        return "\(photos.count) displayed"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { openLibrary() } label: { Label("Open Library", systemImage: "folder") }
        }
        ToolbarItem(placement: .automatic) {
            Toggle("Save edits", isOn: $store.writesEnabled)
                .help("When on, ratings, flags and labels are written back to the library on disk.")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $store.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Switch between Grid, Split, and Viewer layouts.")
        }
    }

    /// On launch: open the last-used library automatically. Hold Option to get
    /// the chooser instead; if there's no prior library, show the open dialog.
    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        let optionDown = NSEvent.modifierFlags.contains(.option)
        if optionDown {
            openLibrary()
        } else if !store.openLastIfAvailable() {
            openLibrary()
        }
    }

    private func newLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.aplibrary"
        panel.message = "Choose where to create the new library"
        panel.prompt = "Create"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension != "aplibrary" {
            url.deletePathExtension()
            url.appendPathExtension("aplibrary")
        }
        do {
            _ = try ApertureLibraryCreator.createLibrary(at: url, firstProjectNamed: "Untitled Project")
            store.open(url: url)
        } catch {
            store.errorMessage = "Couldn't create library: \(error)"
        }
    }

    private func openLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose an Aperture library (.aplibrary)"
        if panel.runModal() == .OK, let url = panel.url {
            store.open(url: url)
        }
    }
}

/// Placeholder shown before a library is opened.
struct ContentUnavailablePlaceholder: View {
    let action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48)).foregroundStyle(Theme.textSecondary)
            Text("No library open").font(.title2).foregroundStyle(Theme.textPrimary)
            Button("Open Library…", action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBackground)
    }
}
