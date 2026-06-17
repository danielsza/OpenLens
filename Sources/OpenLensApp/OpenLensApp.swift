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
                Button("Open Library…") {
                    NotificationCenter.default.post(name: .openLibraryRequested, object: nil)
                }
                .keyboardShortcut("o")
            }
        }
    }
}

extension Notification.Name {
    static let openLibraryRequested = Notification.Name("openLibraryRequested")
}
