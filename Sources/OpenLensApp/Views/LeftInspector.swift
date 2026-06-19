import SwiftUI

/// Aperture's left panel combined Library / Info / Adjustments into one tabbed
/// inspector. This reproduces that: a segmented tab switcher on top, with the
/// sources list, photo info, or adjustments below.
struct LeftInspector: View {
    @ObservedObject var store: LibraryStore
    @State private var tab: Tab = .library

    enum Tab: String, CaseIterable { case library = "Library", info = "Info", adjustments = "Adjustments" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider().overlay(Theme.hairline)

            switch tab {
            case .library: ProjectSidebar(store: store)
            case .info: InfoInspector(store: store)
            case .adjustments: AdjustmentsInspector(store: store)
            }
        }
        .background(Theme.panel)
    }
}
