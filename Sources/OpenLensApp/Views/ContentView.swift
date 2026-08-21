import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenLensKit

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @State private var didAutoOpen = false
    @State private var showExport = false
    @State private var showSlideshow = false
    @State private var showLightTable = false
    @State private var showPlaces = false
    @State private var showDuplicates = false
    @State private var showCompare = false

    var body: some View {
        mainView
            .background(eventHandlers)
            .background(photoEventHandlers)
            .background(smartAlbumHandler)
            .background(sheets)
            .onAppear { store.loadSmartAlbums(); store.loadKnownLibraries(); autoOpenIfNeeded() }
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
            .onReceive(NotificationCenter.default.publisher(for: .backupRequested)) { _ in
                backupLibrary()
            }
    }

    private var mainView: some View {
        HSplitView {
            if !store.fullScreenMode {
                LeftInspector(store: store)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            }
            centerColumn
                .frame(minWidth: 520)
        }
        .background(store.fullScreenMode ? Color.black : Theme.appBackground)
        .navigationTitle(windowTitle)
        .toolbar { toolbarContent }
        .overlay {
            if store.library == nil {
                ContentUnavailablePlaceholder(store: store)
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = store.importProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(radius: 6)
                .padding(.bottom, 60)
            }
        }
    }

    /// Notification handlers + the error alert, hung off a trivial base view so
    /// the type-checker handles the long chain quickly.
    private var eventHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
                if store.library != nil { showExport = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .slideshowRequested)) { _ in
                if !store.visiblePhotos.isEmpty { showSlideshow = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lightTableRequested)) { _ in
                if !store.visiblePhotos.isEmpty { showLightTable = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .placesRequested)) { _ in
                if store.library != nil { showPlaces = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicatesRequested)) { _ in
                if store.library != nil { showDuplicates = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareRequested)) { _ in
                if store.library != nil { showCompare = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printRequested)) { _ in
                printSelected()
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
            .sheet(isPresented: $showPlaces) { PlacesMapView(store: store, isPresented: $showPlaces) }
            .sheet(isPresented: $showDuplicates) { DuplicatesView(store: store, isPresented: $showDuplicates) }
            .sheet(isPresented: $showCompare) { CompareView(store: store, isPresented: $showCompare) }
            .sheet(isPresented: $store.showLibraryChooser) {
                LibraryChooserView(store: store, embedded: false)
            }
    }

    /// Prints ALL selected photos, one per page (aspect-fit).
    private func printSelected() {
        guard let lib = store.library else { return }
        let ids = store.selectedPhotoIDs.isEmpty
            ? [store.selectedPhotoID].compactMap { $0 }
            : Array(store.selectedPhotoIDs)
        let photos = store.visiblePhotos.filter { ids.contains($0.id) }
        guard !photos.isEmpty else { return }
        Task {
            var images: [NSImage] = []
            for photo in photos {
                if let image = await ImageCache.shared.fullImage(for: photo, in: lib) {
                    images.append(image)
                }
            }
            guard !images.isEmpty else { return }
            await MainActor.run {
                let info = NSPrintInfo.shared
                info.horizontalPagination = .fit
                info.verticalPagination = .automatic
                if images.count == 1 {
                    info.orientation = images[0].size.width >= images[0].size.height
                        ? .landscape : .portrait
                }
                let page = info.imageablePageBounds.size
                // One image per page: a tall container that AppKit paginates.
                let container = NSView(frame: NSRect(
                    x: 0, y: 0, width: page.width,
                    height: page.height * CGFloat(images.count)))
                for (index, image) in images.enumerated() {
                    let view = NSImageView(image: image)
                    view.imageScaling = .scaleProportionallyUpOrDown
                    view.frame = NSRect(
                        x: 0,
                        y: page.height * CGFloat(images.count - 1 - index),
                        width: page.width, height: page.height)
                    container.addSubview(view)
                }
                let op = NSPrintOperation(view: container, printInfo: info)
                op.jobTitle = photos.count == 1
                    ? photos[0].version.name
                    : "\(photos.count) photos"
                op.run()
            }
        }
    }

    // MARK: - Center column

    private var centerColumn: some View {
        VStack(spacing: 0) {
            if !store.fullScreenMode {
                filterBar
                Divider().overlay(Theme.hairline)
            }
            content
            if store.viewMode != .split {
                // Split view carries its own control strip under the viewer.
                Divider().overlay(Theme.hairline)
                ControlBar(store: store)
            }
        }
        .background(Theme.appBackground)
        .background(keyboardShortcuts)
        .focusable()
        .focusEffectDisabled()
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
            // F = full-screen editing mode (Aperture muscle memory); Esc exits.
            Button("") { toggleFullScreenMode() }
                .keyboardShortcut("f", modifiers: [])
            Button("") { if store.fullScreenMode { toggleFullScreenMode() } }
                .keyboardShortcut(.escape, modifiers: [])
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
                VStack(spacing: 0) {
                    ControlBar(store: store)
                    Divider().overlay(Theme.hairline)
                    Filmstrip(store: store)
                }
                .frame(height: store.filmstripThumbSize * 0.72 + 26 + 38)
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
            .pickerStyle(.menu).frame(width: 108)

            Toggle(isOn: $store.filter.flaggedOnly) {
                Image(systemName: "flag")
            }
            .toggleStyle(.button)
            .help("Show only flagged photos")

            Toggle(isOn: $store.filter.adjustedOnly) {
                Image(systemName: "wrench")
            }
            .toggleStyle(.button)
            .help("Show only edited photos")

            TextField("Search name or keyword", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 160, maxWidth: 190)

            Picker("Sort", selection: $store.sort) {
                ForEach(PhotoSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).frame(width: 128)
            Button {
                store.sortAscending.toggle()
            } label: {
                Image(systemName: store.sortAscending ? "arrow.up" : "arrow.down")
            }
            .help("Sort direction")

            Spacer(minLength: 8)
            Text(statusText)
                .foregroundStyle(Theme.textSecondary).font(.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 5)
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
                Button("Import as Referenced (keep in place)…") { importPhotos(referenced: true) }
                    .disabled(store.projects.isEmpty)
                Button("Import Folder as Projects…") { importFolderTree() }
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
    /// F-mode = hide panels AND take the window into real macOS full screen
    /// (and back out on exit).
    private func toggleFullScreenMode() {
        store.fullScreenMode.toggle()
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        if store.fullScreenMode != isFullScreen {
            window?.toggleFullScreen(nil)
        }
    }

    private func autoOpenIfNeeded() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        // Aperture behaviour: open the last library on launch; holding Option
        // (or having no last library) lands on the library chooser instead.
        let optionDown = NSEvent.modifierFlags.contains(.option)
        if !optionDown {
            _ = store.openLastIfAvailable()
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

    private func importPhotos(referenced: Bool = false) {
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
        panel.message = referenced
            ? "Choose photos to import — files stay in their current location"
            : "Choose photos to import into the project"
        guard panel.runModal() == .OK else { return }
        let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
        var failed = 0
        for url in panel.urls {
            do { _ = try writer.importImage(at: url, intoProject: projectUuid, referenced: referenced) }
            catch { failed += 1 }
        }
        store.reload()
        store.selectProject(projectUuid)
        if failed > 0 { store.errorMessage = "\(failed) file(s) couldn't be imported." }
    }

    private func backupLibrary() {
        guard let lib = store.library else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Back Up Here"
        panel.message = "Choose where to store the library backup (vault)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task.detached {
            do {
                let (url, report) = try lib.createVault(in: dest)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = report.isHealthy ? "Backup complete" : "Backup completed with warnings"
                    alert.informativeText = report.isHealthy
                        ? "Verified backup at \(url.lastPathComponent)."
                        : "\(report.issues.count) issue(s) found in the backup — see --verify."
                    alert.runModal()
                }
            } catch {
                await MainActor.run { store.errorMessage = "Backup failed: \(error)" }
            }
        }
    }

    private func importFolderTree() {
        guard let lib = store.library else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder — each subfolder with images becomes a project"
        guard panel.runModal() == .OK, let root = panel.url else { return }
        let libURL = lib.url
        store.importProgress = "Scanning \(root.lastPathComponent)…"
        Task.detached(priority: .userInitiated) {
            let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
            do {
                let result = try writer.importFolderTree(at: root) { message in
                    Task { @MainActor in store.importProgress = message }
                }
                await MainActor.run {
                    store.importProgress = nil
                    store.reload()
                    if result.photosImported == 0 {
                        store.errorMessage = "No images found in \(root.lastPathComponent)."
                    }
                }
            } catch {
                await MainActor.run {
                    store.importProgress = nil
                    store.errorMessage = "Folder import failed: \(error)"
                }
            }
        }
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

    private func newLibrary() { store.newLibraryPanel() }
    private func openLibrary() { store.openLibraryPanel() }
}

/// Empty-window state: shows the Aperture/Photos-style Choose Library dialog
/// as a centred card.
struct ContentUnavailablePlaceholder: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        ZStack {
            Theme.appBackground
            LibraryChooserView(store: store, embedded: true)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.black.opacity(0.25)))
                .shadow(radius: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
