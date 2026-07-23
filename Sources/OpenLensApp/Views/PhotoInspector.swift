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
    @State private var newKeyword: String = ""
    @State private var captionField = ""
    @State private var titleField = ""
    @State private var bylineField = ""
    @State private var copyrightField = ""

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

                    keywordEditor(photo)

                    Divider()
                    iptcEditor(photo)

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
        self.captionField = meta?.caption ?? ""
        self.titleField = meta?.title ?? ""
        self.bylineField = meta?.byline ?? ""
        self.copyrightField = meta?.copyright ?? ""
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
            if let lib = store.library {
                row("Viewer shows", lib.previewURL(for: photo) != nil ? "Rendered preview (with edits)" : "Original master")
            }
            if let lat = photo.version.latitude, let lon = photo.version.longitude {
                row("Location", String(format: "%.4f, %.4f", lat, lon))
            }
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

    @ViewBuilder
    private func keywordEditor(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keywords").font(.caption).foregroundStyle(.secondary)
            if !keywords.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(keywords, id: \.self) { kw in
                        HStack(spacing: 3) {
                            Text(kw).font(.caption2).lineLimit(1)
                            Button {
                                store.removeKeyword(kw, from: photo)
                                keywords.removeAll { $0 == kw }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                    }
                }
            }
            TextField("Add keyword", text: $newKeyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addKeyword(photo) }
        }
    }

    @ViewBuilder
    private func iptcEditor(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Metadata").font(.caption).foregroundStyle(.secondary)
            labeledField("Title", text: $titleField) { save(photo) }
            labeledField("Caption", text: $captionField) { save(photo) }
            labeledField("Byline", text: $bylineField) { save(photo) }
            labeledField("Copyright", text: $copyrightField) { save(photo) }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.roundedBorder).font(.caption)
                .onSubmit(onCommit)
        }
    }

    private func save(_ photo: Photo) {
        store.setIPTC(photo,
                      caption: captionField, title: titleField,
                      byline: bylineField, copyright: copyrightField)
    }

    private func addKeyword(_ photo: Photo) {
        let name = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !keywords.contains(name) else { newKeyword = ""; return }
        if store.addKeyword(name, to: photo) {
            keywords.append(name)
            keywords.sort()
        }
        newKeyword = ""
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
    @State private var apertureAdjustments: [String] = []
    @State private var histogram: ImageLoader.Histogram?
    @State private var params = OLAdjustments()
    @State private var savedParams = OLAdjustments()

    private var isDirty: Bool { params != savedParams }

    var body: some View {
        if let photo = store.selectedPhoto {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Histogram").font(.headline)
                    HistogramView(histogram: histogram)
                        .frame(height: 90)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Divider()
                    Text("Adjustments").font(.headline)

                    slider("Exposure", $params.exposure, -2...2)
                    slider("Contrast", $params.contrast, 0.5...1.5)
                    slider("Saturation", $params.saturation, 0...2)
                    slider("Temperature", $params.temperature, -100...100)
                    slider("Tint", $params.tint, -100...100)
                    slider("Highlights", $params.highlights, -1...1)
                    slider("Shadows", $params.shadows, -1...1)
                    slider("Sharpness", $params.sharpness, 0...1)

                    HStack {
                        Button("Reset") {
                            params = OLAdjustments()
                            store.previewAdjustments(params)
                        }
                        .disabled(params.isIdentity && savedParams.isIdentity)
                        Spacer()
                        Button("Save") { save(photo) }
                            .keyboardShortcut("s", modifiers: [.command])
                            .disabled(!isDirty)
                            .buttonStyle(.borderedProminent)
                    }
                    if !store.writesEnabled && isDirty {
                        Text("Turn on “Save edits” in the toolbar to persist.")
                            .font(.caption2).foregroundStyle(.orange)
                    }

                    if !apertureAdjustments.isEmpty {
                        Divider()
                        Text("Aperture edits on this photo").font(.caption).foregroundStyle(.secondary)
                        ForEach(apertureAdjustments, id: \.self) { a in
                            Label(a, systemImage: "slider.horizontal.3").font(.caption)
                        }
                        Text("Shown via Aperture's rendered preview; re-editing them requires the adjustment decoder (planned).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Theme.panel)
            .task(id: photo.id) { await load(photo) }
        } else {
            ZStack { Theme.panel; Text("Select a photo").foregroundStyle(.secondary) }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; store.previewAdjustments(params) }
            ), in: range)
        }
    }

    private func save(_ photo: Photo) {
        store.saveAdjustments(params, for: photo)
        savedParams = params
    }

    private func load(_ photo: Photo) async {
        guard let lib = store.library else { apertureAdjustments = []; histogram = nil; return }
        let all = (try? lib.enabledAdjustmentNames(for: photo)) ?? []
        apertureAdjustments = all.filter { $0 != "OLAdjustmentsV1" }
        savedParams = lib.olAdjustments(for: photo) ?? OLAdjustments()
        params = savedParams
        histogram = nil
        let url = lib.displayImageURL(for: photo)
        histogram = await Task.detached(priority: .utility) {
            ImageLoader.histogram(at: url)
        }.value
    }
}

/// Draws a luminance histogram as bars.
private struct HistogramView: View {
    let histogram: ImageLoader.Histogram?
    var body: some View {
        GeometryReader { geo in
            if let h = histogram, let maxV = h.luminance.max(), maxV > 0 {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(h.luminance.enumerated()), id: \.offset) { _, v in
                        Rectangle()
                            .fill(.white.opacity(0.8))
                            .frame(height: geo.size.height * CGFloat(v) / CGFloat(maxV))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                Text("—").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
