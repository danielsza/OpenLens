import SwiftUI
import AppKit
import OpenLensKit

/// The Aperture/Photos-style "Choose Library" dialog: app icon + blurb, a
/// bordered selectable list of known libraries ("(Last Opened)" annotated),
/// the selected library's path, and Other Library… / Create New… / Choose
/// Library buttons. Shown embedded when no library is open, or as a sheet
/// via ⌥⌘O.
struct LibraryChooserView: View {
    @ObservedObject var store: LibraryStore
    /// true = filling the empty-window state; false = presented as a sheet.
    var embedded: Bool

    @State private var selection: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose Library").font(.title3.bold())
                    Text("Choose a photo library from the list, find another library on your computer, or create a new library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            libraryList

            Text(selection?.path ?? " ")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Other Library…") {
                    closeSheetIfNeeded()
                    store.openLibraryPanel()
                }
                Button("Create New…") {
                    closeSheetIfNeeded()
                    store.newLibraryPanel()
                }
                Spacer()
                if !embedded {
                    Button("Cancel") { store.showLibraryChooser = false }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Choose Library") {
                    if let selection { choose(selection) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            store.loadKnownLibraries()
            selection = store.lastLibraryURL ?? store.knownLibraries.first
        }
    }

    private var libraryList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.knownLibraries.isEmpty {
                    Text("No libraries known yet — use “Other Library…” to find one.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                ForEach(Array(store.knownLibraries.enumerated()), id: \.element.path) { index, url in
                    let isSelected = selection?.path == url.path
                    HStack {
                        Text(rowTitle(url))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(isSelected
                                ? Color.accentColor
                                : (index.isMultiple(of: 2) ? Color.clear
                                                           : Color.primary.opacity(0.04)))
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded { choose(url) })
                    .simultaneousGesture(TapGesture().onEnded { selection = url })
                }
            }
        }
        .frame(height: 190)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2))
    }

    private func rowTitle(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if url.path == store.lastLibraryURL?.path { return "\(name)  (Last Opened)" }
        if url.path == store.library?.url.path { return "\(name)  (Open)" }
        return name
    }

    private func choose(_ url: URL) {
        closeSheetIfNeeded()
        store.open(url: url)
    }

    private func closeSheetIfNeeded() {
        if !embedded { store.showLibraryChooser = false }
    }
}
