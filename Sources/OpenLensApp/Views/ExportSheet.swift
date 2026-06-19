import SwiftUI
import AppKit
import OpenLensKit

/// Aperture-style export dialog: format, size, resolution, quality, watermark.
struct ExportSheet: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var format: ExportSettings.Format = .jpeg
    @State private var maxEdge: Int = 0
    @State private var quality: Double = 0.9
    @State private var dpiText: String = ""
    @State private var watermarkText: String = ""
    @State private var watermarkImageURL: URL?
    @State private var watermarkScale: Double = 0.25
    @State private var watermarkPosition: Watermark.Position = .bottomCenter
    @State private var watermarkOpacity: Double = 0.5
    @State private var selectionOnly = true

    private var selectionCount: Int {
        store.selectedPhotoIDs.isEmpty ? (store.selectedPhotoID == nil ? 0 : 1) : store.selectedPhotoIDs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Photos").font(.title2).bold()

            Form {
                Picker("Format", selection: $format) {
                    Text("Original files").tag(ExportSettings.Format.originals)
                    Text("JPEG").tag(ExportSettings.Format.jpeg)
                    Text("PNG").tag(ExportSettings.Format.png)
                    Text("TIFF").tag(ExportSettings.Format.tiff)
                }

                if format != .originals {
                    Picker("Size", selection: $maxEdge) {
                        Text("Full size").tag(0)
                        Text("4096 px").tag(4096)
                        Text("2048 px").tag(2048)
                        Text("1024 px").tag(1024)
                        Text("640 px").tag(640)
                    }
                    if format == .jpeg {
                        HStack {
                            Text("Quality")
                            Slider(value: $quality, in: 0.3...1.0)
                            Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 42)
                        }
                    }
                    TextField("Resolution (DPI, optional)", text: $dpiText)

                    Divider()
                    Text("Watermark").font(.headline)
                    TextField("Text (leave blank for none)", text: $watermarkText)

                    HStack {
                        Text("Logo")
                        if let url = watermarkImageURL {
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Button("Clear") { watermarkImageURL = nil }
                        } else {
                            Text("None").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Image…") { chooseLogo() }
                    }
                    if watermarkImageURL != nil {
                        HStack {
                            Text("Logo size")
                            Slider(value: $watermarkScale, in: 0.05...0.6)
                            Text("\(Int(watermarkScale * 100))%").monospacedDigit().frame(width: 42)
                        }
                    }

                    Picker("Position", selection: $watermarkPosition) {
                        ForEach(Watermark.Position.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack {
                        Text("Opacity")
                        Slider(value: $watermarkOpacity, in: 0.1...1.0)
                    }
                }

                Divider()
                Picker("Export", selection: $selectionOnly) {
                    Text("Selection (\(selectionCount))").tag(true)
                    Text("All shown (\(store.visiblePhotos.count))").tag(false)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { runExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.library == nil || photosToExport().isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func photosToExport() -> [Photo] {
        if selectionOnly {
            let ids = store.selectedPhotoIDs.isEmpty
                ? Set([store.selectedPhotoID].compactMap { $0 })
                : store.selectedPhotoIDs
            return store.visiblePhotos.filter { ids.contains($0.id) }
        }
        return store.visiblePhotos
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a watermark/logo image (PNG with transparency works best)"
        if panel.runModal() == .OK { watermarkImageURL = panel.url }
    }

    private func runExport() {
        guard let lib = store.library else { return }
        let photos = photosToExport()
        guard !photos.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a destination folder"
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        var watermark: Watermark?
        if let logo = watermarkImageURL {
            watermark = Watermark(imageURL: logo, opacity: watermarkOpacity,
                                  scale: watermarkScale, position: watermarkPosition)
        } else if !watermarkText.trimmingCharacters(in: .whitespaces).isEmpty {
            watermark = Watermark(text: watermarkText, opacity: watermarkOpacity, position: watermarkPosition)
        }
        let settings = ExportSettings(
            format: format, maxPixelSize: maxEdge, jpegQuality: quality,
            dpi: Double(dpiText.trimmingCharacters(in: .whitespaces)), watermark: watermark)

        let exporter = Exporter(library: lib)
        let result = exporter.exportBatch(photos, to: dest, settings: settings)
        isPresented = false
        if !result.failures.isEmpty {
            store.errorMessage = "\(result.failures.count) of \(photos.count) photo(s) failed to export."
        }
    }
}
