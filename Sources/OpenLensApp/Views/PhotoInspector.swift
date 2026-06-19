import SwiftUI
import AppKit
import CoreGraphics
import OpenLensKit

/// The "Info" inspector tab: a small preview, rating/flag, and metadata.
struct InfoInspector: View {
    @ObservedObject var store: LibraryStore
    @State private var preview: NSImage?
    @State private var meta: VersionMetadata?
    @State private var keywords: [String] = []

    var body: some View {
        if let photo = store.selectedPhoto {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(photo.version.name).font(.headline)

                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                                .foregroundStyle(star <= photo.version.rating ? .yellow : .secondary)
                                .onTapGesture {
                                    store.setRating(photo.version.rating == star ? 0 : star, for: photo)
                                }
                        }
                        Spacer()
                        Button { store.toggleFlag(for: photo) } label: {
                            Image(systemName: photo.version.isFlagged ? "flag.fill" : "flag")
                        }.buttonStyle(.plain)
                    }

                    Divider()
                    metadata(photo)

                    if !keywords.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keywords").font(.caption).foregroundStyle(.secondary)
                            Text(keywords.joined(separator: ", ")).font(.caption)
                        }
                    }

                    Divider()
                    Button { openInExternalEditor(photo) } label: {
                        Label("Open in External Editor", systemImage: "square.and.pencil")
                    }
                    .help("Opens the master file in your default image editor.")
                }
                .padding()
            }
            .background(Theme.panel)
            .task(id: photo.id) { await load(photo) }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack { Theme.panel; Text("Select a photo").foregroundStyle(.secondary) }
    }

    private func load(_ photo: Photo) async {
        preview = nil
        guard let library = store.library else { return }
        self.meta = library.metadata(for: photo)
        self.keywords = (try? library.keywords(for: photo)) ?? []
        let url = library.displayImageURL(for: photo)
        let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            ImageLoader.cgImage(at: url, maxPixelSize: 600)
        }.value
        if let cg {
            self.preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    @ViewBuilder
    private func metadata(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("File", photo.master.fileName)
            if let date = photo.version.imageDate {
                row("Date", date.formatted(date: .abbreviated, time: .shortened))
            }
            if let w = photo.version.masterWidth, let h = photo.version.masterHeight {
                row("Dimensions", "\(w) × \(h)")
            }
            row("Type", photo.master.type)
            if photo.version.hasAdjustments { row("Edited", "Yes") }
            if photo.master.isReference { row("Referenced", "Yes") }
            if let meta {
                let camera = [meta.cameraMake, meta.cameraModel].compactMap { $0 }.joined(separator: " ")
                if !camera.isEmpty { row("Camera", camera) }
                if let lens = meta.lensModel { row("Lens", lens) }
                if !meta.exposureSummary.isEmpty { row("Exposure", meta.exposureSummary) }
                if let copyright = meta.copyright, !copyright.isEmpty { row("Copyright", copyright) }
            }
        }
        .font(.caption)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
    }

    private func openInExternalEditor(_ photo: Photo) {
        guard let library = store.library else { return }
        NSWorkspace.shared.open(library.masterFileURL(for: photo.master))
    }
}

/// The "Adjustments" inspector tab. Lists the adjustments on the selected
/// photo; editing is a future milestone.
struct AdjustmentsInspector: View {
    @ObservedObject var store: LibraryStore
    @State private var adjustments: [String] = []

    var body: some View {
        if let photo = store.selectedPhoto {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Adjustments").font(.headline)
                    if adjustments.isEmpty {
                        Text("No adjustments on this photo")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(adjustments, id: \.self) { a in
                            Label(a, systemImage: "slider.horizontal.3").font(.callout)
                        }
                    }
                    Divider()
                    Text("Adjustment editing is coming soon.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Theme.panel)
            .task(id: photo.id) {
                if let lib = store.library {
                    adjustments = (try? lib.enabledAdjustmentNames(for: photo)) ?? []
                } else {
                    adjustments = []
                }
            }
        } else {
            ZStack { Theme.panel; Text("Select a photo").foregroundStyle(.secondary) }
        }
    }
}
