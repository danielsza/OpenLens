import SwiftUI
import AppKit
import Sparkle

/// Sparkle auto-update controller (checks the appcast published with each
/// GitHub Release; updates install without Gatekeeper quarantine nags).
final class UpdaterModel: ObservableObject {
    let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
}

@main
struct OpenLensApp: App {
    @StateObject private var updater = UpdaterModel()
    // App-owned so the File menu works even with every window closed.
    @StateObject private var store = LibraryStore()

    init() {
        // When run as a Swift Package executable (swift run OpenLensApp),
        // promote the process to a regular app so its window comes forward.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("OpenLens", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            LibraryCommands(store: store)
            // Replace the About group so both items reliably render in the
            // app menu (the `after: .appInfo` insertion doesn't show for
            // SPM-built apps).
            CommandGroup(replacing: .appInfo) {
                Button("About OpenLens") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
                Button("Check for Updates…") {
                    updater.controller.checkForUpdates(nil)
                }
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Export…") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Save Filter as Smart Album…") {
                    NotificationCenter.default.post(name: .saveSmartAlbumRequested, object: nil)
                }
                Button("Back Up Library…") {
                    NotificationCenter.default.post(name: .backupRequested, object: nil)
                }
            }
            // Append to the system View menu (a CommandMenu("View") would
            // create a duplicate second "View" menu).
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Start Slideshow") {
                    NotificationCenter.default.post(name: .slideshowRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Light Table") {
                    NotificationCenter.default.post(name: .lightTableRequested, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Places") {
                    NotificationCenter.default.post(name: .placesRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Find Duplicates") {
                    NotificationCenter.default.post(name: .duplicatesRequested, object: nil)
                }
                Button("Compare Selected") {
                    NotificationCenter.default.post(name: .compareRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .printRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            CommandMenu("Photo") {
                Button("Duplicate Version") {
                    NotificationCenter.default.post(name: .duplicateVersionRequested, object: nil)
                }
                .keyboardShortcut("d")
                Divider()
                Button("Rotate Left") {
                    NotificationCenter.default.post(name: .rotateLeftRequested, object: nil)
                }
                .keyboardShortcut("[")
                Button("Rotate Right") {
                    NotificationCenter.default.post(name: .rotateRightRequested, object: nil)
                }
                .keyboardShortcut("]")
                Divider()
                Button("Auto-Stack by Time") {
                    NotificationCenter.default.post(name: .autoStackRequested, object: nil)
                }
                Divider()
                Button("Move to Trash") {
                    NotificationCenter.default.post(name: .moveToTrashRequested, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                Button("Put Back") {
                    NotificationCenter.default.post(name: .restoreRequested, object: nil)
                }
                Button("Empty Trash…") {
                    NotificationCenter.default.post(name: .emptyTrashRequested, object: nil)
                }
            }
        }
    }
}

/// The library-lifecycle File-menu items. These talk to the app-owned store
/// directly (NOT via window notifications) so they keep working after every
/// window is closed — and reopen the main window when needed.
struct LibraryCommands: Commands {
    @ObservedObject var store: LibraryStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Library…") {
                ensureWindow()
                store.newLibraryPanel()
            }
            .keyboardShortcut("n")

            // ⌘O = open the last library (Aperture behaviour);
            // ⌥⌘O = the Choose Library dialog.
            Button("Open Last Library") {
                ensureWindow()
                if store.library == nil, !store.openLastIfAvailable() {
                    store.showLibraryChooser = true
                }
            }
            .keyboardShortcut("o")

            Button("Choose Library…") {
                ensureWindow()
                store.showLibraryChooser = true
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Menu("Switch to Library") {
                if store.knownLibraries.isEmpty {
                    Button("No Known Libraries") {}.disabled(true)
                }
                ForEach(store.knownLibraries, id: \.path) { url in
                    Button(libraryTitle(url)) {
                        ensureWindow()
                        store.open(url: url)
                    }
                }
            }

            Button("Close Library") { store.closeLibrary() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }

    private func libraryTitle(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let isCurrent = store.library?.url.path == url.path
        return isCurrent ? "\(name) ✓" : name
    }

    private func ensureWindow() {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let newLibraryRequested = Notification.Name("newLibraryRequested")
    static let duplicateVersionRequested = Notification.Name("duplicateVersionRequested")
    static let rotateLeftRequested = Notification.Name("rotateLeftRequested")
    static let rotateRightRequested = Notification.Name("rotateRightRequested")
    static let autoStackRequested = Notification.Name("autoStackRequested")
    static let moveToTrashRequested = Notification.Name("moveToTrashRequested")
    static let restoreRequested = Notification.Name("restoreRequested")
    static let emptyTrashRequested = Notification.Name("emptyTrashRequested")
    static let exportRequested = Notification.Name("exportRequested")
    static let saveSmartAlbumRequested = Notification.Name("saveSmartAlbumRequested")
    static let backupRequested = Notification.Name("backupRequested")
    static let slideshowRequested = Notification.Name("slideshowRequested")
    static let lightTableRequested = Notification.Name("lightTableRequested")
    static let placesRequested = Notification.Name("placesRequested")
    static let duplicatesRequested = Notification.Name("duplicatesRequested")
    static let compareRequested = Notification.Name("compareRequested")
    static let printRequested = Notification.Name("printRequested")
    static let openLibraryRequested = Notification.Name("openLibraryRequested")
    static let closeLibraryRequested = Notification.Name("closeLibraryRequested")
}
