import SwiftUI
import OpenLensKit

/// Lists byte-identical duplicate masters so the user can review and trash
/// the extras.
struct DuplicatesView: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var groups: [[Photo]]?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Duplicates").font(.headline)
                if let groups {
                    Text(groups.isEmpty ? "No duplicates found ✓"
                                        : "\(groups.count) group(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()

            if let groups {
                if groups.isEmpty {
                    Text("Every master file in this library is unique.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.map { $0.version.name }.joined(separator: "  ·  "))
                                        .font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        ForEach(group) { photo in
                                            VStack(spacing: 4) {
                                                PhotoThumbnail(store: store, photo: photo,
                                                               size: 120, showCaption: false)
                                                Button("Trash this copy") {
                                                    store.moveToTrash(photo)
                                                    refresh()
                                                }
                                                .font(.caption2)
                                            }
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(14)
                    }
                }
            } else {
                ProgressView("Scanning for duplicates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { refresh() }
    }

    private func refresh() {
        groups = nil
        guard let lib = store.library else { groups = []; return }
        Task.detached(priority: .userInitiated) {
            let found = (try? lib.findDuplicates()) ?? []
            await MainActor.run { groups = found }
        }
    }
}
