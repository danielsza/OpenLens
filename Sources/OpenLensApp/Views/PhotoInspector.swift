import SwiftUI
import AppKit
import CoreGraphics
import OpenLensKit

struct PhotoInspector: View {
    @ObservedObject var store: LibraryStore
    @State private var preview: NSImage?
    @State private var meta: VersionMetadata?
    @State private var keywords: [String] = []
    @State private var adjustments: [String] = []

    var body: some View {
        if let photo = store.selectedPhoto {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(photo.version.name).font(.title3).bold()

                    // Rating
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rating").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                                    .foregroundStyle(star <= photo.version.rating ? .yellow : .secondary)
                                    .onTapGesture {
                                        let newRating = (photo.version.rating == star) ? 0 : star
                                        store.setRating(newRating, for: photo)
                                    }
                            }
                        }
                    }

                    Button {
                        store.toggleFlag(for: photo)
                    } label: {
                        Label(photo.version.isFlagged ? "Flagged" : "Flag",
                              systemImage: photo.version.isFlagged ? "flag.fill" : "flag")
                    }

                    Divider()

                    // Metadata
                    metadata(photo)

                    if !keywords.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keywords").font(.caption).foregroundStyle(.secondary)
                            Text(keywords.joined(separator: ", ")).font(.caption)
                        }
                    }

                    if !adjustments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adjustments").font(.caption).foregroundStyle(.secondary)
                            Text(adjustments.joined(separator: ", ")).font(.caption)
                        }
                    }

                    Divider()

                    Button {
                        openInExternalEditor(photo)
                    } label: {
                        Label("Open in External Editor", systemImage: "square.and.pencil")
                    }
                    .help("Opens the master file in your default image editor.")
                }
                .padding()
            }
            .task(id: photo.id) { await load(photo) }
        } else {
            Text("Select a photo")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load(_ photo: Photo) async {
        preview = nil
        guard let library = store.library else { return }
        self.meta = library.metadata(for: photo)
        self.keywords = (try? library.keywords(for: photo)) ?? []
        self.adjustments = (try? library.enabledAdjustmentNames(for: photo)) ?? []
        let url = library.displayImageURL(for: photo)
        let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            ImageLoader.cgImage(at: url, maxPixelSize: 800)
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
                if let copyright = meta.copyright, !copyright.isEmpty {
                    row("Copyright", copyright)
                }
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
        let url = library.masterFileURL(for: photo.master)
        NSWorkspace.shared.open(url)
    }
}
