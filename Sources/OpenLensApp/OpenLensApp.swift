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
                Divider()
                Button("Export…") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Save Filter as Smart Album…") {
                    NotificationCenter.default.post(name: .saveSmartAlbumRequested, object: nil)
                }
            }
            CommandMenu("View") {
                Button("Start Slideshow") {
                    NotificationCenter.default.post(name: .slideshowRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Light Table") {
                    NotificationCenter.default.post(name: .lightTableRequested, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
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
    static let slideshowRequested = Notification.Name("slideshowRequested")
    static let lightTableRequested = Notification.Name("lightTableRequested")
    static let openLibraryRequested = Notification.Name("openLibraryRequested")
    static let closeLibraryRequested = Notification.Name("closeLibraryRequested")
}
