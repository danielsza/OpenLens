import SwiftUI
import AppKit

@main
struct OpenLensApp: App {
    init() {
        // When run as a Swift Package executable (swift run OpenLensApp),
        // promote the process to a regular app so its window comes forward.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("OpenLens") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Library…") {
                    NotificationCenter.default.post(name: .newLibraryRequested, object: nil)
                }
                .keyboardShortcut("n")
                Button("Open / Switch Library…") {
                    NotificationCenter.default.post(name: .openLibraryRequested, object: nil)
                }
                .keyboardShortcut("o")
                Button("Close Library") {
                    NotificationCenter.default.post(name: .closeLibraryRequested, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandMenu("Photo") {
                Button("Duplicate Version") {
                    NotificationCenter.default.post(name: .duplicateVersionRequested, object: nil)
                }
                .keyboardShortcut("d")
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

extension Notification.Name {
    static let newLibraryRequested = Notification.Name("newLibraryRequested")
    static let duplicateVersionRequested = Notification.Name("duplicateVersionRequested")
    static let moveToTrashRequested = Notification.Name("moveToTrashRequested")
    static let restoreRequested = Notification.Name("restoreRequested")
    static let emptyTrashRequested = Notification.Name("emptyTrashRequested")
    static let openLibraryRequested = Notification.Name("openLibraryRequested")
    static let closeLibraryRequested = Notification.Name("closeLibraryRequested")
}
