import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenLensKit

struct ContentView: View {
    @StateObject private var store = LibraryStore()
    @State private var didAutoOpen = false
    @State private var showExport = false
    @State private var showSlideshow = false
    @State private var showLightTable = false

    var body: some View {
        mainView
            .background(eventHandlers)
            .background(photoEventHandlers)
            .background(smartAlbumHandler)
            .background(sheets)
            .onAppear { store.loadSmartAlbums(); autoOpenIfNeeded() }
    }

    private var smartAlbumHandler: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .saveSmartAlbumRequested)) { _ in
                if let name = promptForName(title: "Save Smart Album", placeholder: "Smart album name") {
                    store.addSmartAlbum(named: name)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoStackRequested)) { _ in
                store.autoStack()
            }
    }

    private var mainView: some View {
        HSplitView {
            LeftInspector(store: store)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            centerColumn
                .frame(minWidth: 520)
        }
        .background(Theme.appBackground)
        .navigationTitle(windowTitle)
        .toolbar { toolbarContent }
        .overlay {
            if store.library == nil {
                ContentUnavailablePlaceholder(action: openLibrary)
            }
        }
    }

    /// Notification handlers + the error alert, hung off a trivial base view so
    /// the type-checker handles the long chain quickly.
    private var eventHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .openLibraryRequested)) { _ in openLibrary() }
            .onReceive(NotificationCenter.default.publisher(for: .newLibraryRequested)) { _ in newLibrary() }
            .onReceive(NotificationCenter.default.publisher(for: .closeLibraryRequested)) { _ in store.closeLibrary() }
            .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
                if store.library != nil { showExport = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .slideshowRequested)) { _ in
                if !store.visiblePhotos.isEmpty { showSlideshow = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lightTableRequested)) { _ in
                if !store.visiblePhotos.isEmpty { showLightTable = true }
            }
            .alert("Library error",
                   isPresented: Binding(get: { store.errorMessage != nil },
                                        set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
    }

    private var photoEventHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .duplicateVersionRequested)) { _ in duplicateSelected() }
            .onReceive(NotificationCenter.default.publisher(for: .rotateLeftRequested)) { _ in store.rotateSelection(clockwise: false) }
            .onReceive(NotificationCenter.default.publisher(for: .rotateRightRequested)) { _ in store.rotateSelection(clockwise: true) }
            .onReceive(NotificationCenter.default.publisher(for: .moveToTrashRequested)) { _ in store.moveSelectionToTrash() }
            .onReceive(NotificationCenter.default.publisher(for: .restoreRequested)) { _ in
                if let p = store.selectedPhoto { store.restoreFromTrash(p) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .emptyTrashRequested)) { _ in confirmEmptyTrash() }
    }

    private var sheets: some View {
        Color.clear
            .sheet(isPresented: $showExport) { ExportSheet(store: store, isPresented: $showExport) }
            .sheet(isPresented: $showSlideshow) { SlideshowView(store: store, isPresented: $showSlideshow) }
            .sheet(isPresented: $showLightTable) { LightTableView(store: store, isPresented: $showLightTable) }
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
                Button("") { store.setRatingForSelection(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [])
            }
            Button("") {
                store.setFlagForSelection(!(store.selectedPhoto?.version.isFlagged ?? false))
            }
            .keyboardShortcut("/", modifiers: [])
            // 9 = Reject (rating -1), as in Aperture.
            Button("") { store.setRatingForSelection(-1) }
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

            Picker("Sort", selection: $store.sort) {
                ForEach(PhotoSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).frame(width: 130)
            Button {
                store.sortAscending.toggle()
            } label: {
                Image(systemName: store.sortAscending ? "arrow.up" : "arrow.down")
            }
            .help("Sort direction")

            Spacer()
            Text(statusText)
                .foregroundStyle(Theme.textSecondary).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.panel)
    }

    private var windowTitle: String {
        guard let lib = store.library else { return "OpenLens" }
        return lib.url.deletingPathExtension().lastPathComponent
    }

    private var statusText: String {
        let photos = store.visiblePhotos
        if store.selectedPhotoIDs.count > 1 {
            return "\(store.selectedPhotoIDs.count) selected — \(photos.count) displayed"
        }
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
            Menu {
                Button("New Project…") { createProject() }
                Button("New Album…") { createAlbum() }
                Divider()
                Button("Import Photos…") { importPhotos() }
                    .disabled(store.projects.isEmpty)
            } label: {
                Label("New", systemImage: "plus")
            }
            .disabled(store.library == nil)
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

    private func createProject() {
        guard let lib = store.library, let name = promptForName(title: "New Project", placeholder: "Project name") else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            let uuid = try writer.createProject(named: name)
            store.reload()
            store.selectProject(uuid)
        } catch { store.errorMessage = "Couldn't create project: \(error)" }
    }

    private func createAlbum() {
        guard let lib = store.library, let name = promptForName(title: "New Album", placeholder: "Album name") else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            let uuid = try writer.createAlbum(named: name)
            store.reload()
            store.selectAlbum(uuid)
        } catch { store.errorMessage = "Couldn't create album: \(error)" }
    }

    private func confirmEmptyTrash() {
        guard store.library != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "This permanently deletes the photos in the trash and their files. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.emptyTrash() }
    }

    private func duplicateSelected() {
        guard let lib = store.library, let photo = store.selectedPhoto else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            let newUuid = try writer.duplicateVersion(photo.version.id)
            store.reload()
            store.selectedPhotoID = newUuid
        } catch { store.errorMessage = "Couldn't duplicate version: \(error)" }
    }

    private func importPhotos() {
        guard let lib = store.library else { return }
        guard let projectUuid = store.selectedProjectID ?? store.projects.first?.id else {
            store.errorMessage = "Create or select a project first."
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose photos to import into the project"
        guard panel.runModal() == .OK else { return }
        let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
        var failed = 0
        for url in panel.urls {
            do { _ = try writer.importImage(at: url, intoProject: projectUuid) }
            catch { failed += 1 }
        }
        store.reload()
        store.selectProject(projectUuid)
        if failed > 0 { store.errorMessage = "\(failed) file(s) couldn't be imported." }
    }

    private func promptForName(title: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
