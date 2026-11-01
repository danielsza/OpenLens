import SwiftUI
import AppKit
import OpenLensKit

/// Aperture-style export dialog: format, size, resolution, quality, watermark.
/// Settings persist across launches via @AppStorage.
struct ExportSheet: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @AppStorage("export.format") private var formatRaw = ExportSettings.Format.jpeg.rawValue
    @AppStorage("export.maxEdge") private var maxEdge = 0          // 0 full, -1 custom
    @AppStorage("export.customEdge") private var customEdge = 1600
    @AppStorage("export.quality") private var quality = 0.9
    @AppStorage("export.dpi") private var dpiText = ""
    @AppStorage("export.suffix") private var nameSuffix = ""
    @AppStorage("export.customName") private var customName = ""
    @AppStorage("export.preserveMeta") private var preserveMetadata = true
    @AppStorage("export.wmText") private var watermarkText = ""
    @AppStorage("export.logoPath") private var logoPath = ""
    @AppStorage("export.wmScale") private var watermarkScale = 0.25
    @AppStorage("export.wmPos") private var positionRaw = Watermark.Position.bottomCenter.rawValue
    @AppStorage("export.wmOpacity") private var watermarkOpacity = 0.5
    @AppStorage("export.selectionOnly") private var selectionOnly = true
    @AppStorage("export.subfolderMode") private var subfolderMode = "none"  // none|project|custom
    @AppStorage("export.subfolderName") private var subfolderName = ""

    private var format: ExportSettings.Format { .init(rawValue: formatRaw) ?? .jpeg }
    private var formatBinding: Binding<ExportSettings.Format> {
        Binding(get: { format }, set: { formatRaw = $0.rawValue })
    }
    private var positionBinding: Binding<Watermark.Position> {
        Binding(get: { Watermark.Position(rawValue: positionRaw) ?? .bottomCenter },
                set: { positionRaw = $0.rawValue })
    }
    private var effectiveMaxEdge: Int { maxEdge == -1 ? max(1, customEdge) : max(0, maxEdge) }
    /// Size-picker tags below -1 encode percent-of-original (e.g. -50 = 50%).
    private var scalePercent: Double { maxEdge < -1 ? Double(-maxEdge) : 0 }
    private var logoURL: URL? { logoPath.isEmpty ? nil : URL(fileURLWithPath: logoPath) }

    private var selectionCount: Int {
        store.selectedPhotoIDs.isEmpty ? (store.selectedPhotoID == nil ? 0 : 1) : store.selectedPhotoIDs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Photos").font(.title2).bold()

            Form {
                Picker("Format", selection: formatBinding) {
                    Text("Original files").tag(ExportSettings.Format.originals)
                    Text("JPEG").tag(ExportSettings.Format.jpeg)
                    Text("PNG").tag(ExportSettings.Format.png)
                    Text("TIFF").tag(ExportSettings.Format.tiff)
                    Text("HEIC").tag(ExportSettings.Format.heic)
                }

                if format != .originals {
                    Picker("Size", selection: $maxEdge) {
                        Text("Full size").tag(0)
                        Text("75%").tag(-75)
                        Text("50%").tag(-50)
                        Text("25%").tag(-25)
                        Text("4096 px").tag(4096)
                        Text("2048 px").tag(2048)
                        Text("1024 px").tag(1024)
                        Text("640 px").tag(640)
                        Text("Custom…").tag(-1)
                    }
                    if maxEdge == -1 {
                        HStack {
                            Text("Long edge")
                            TextField("px", value: $customEdge, format: .number).frame(width: 80)
                            Text("px").foregroundStyle(.secondary)
                        }
                    }
                    if format == .jpeg || format == .heic {
                        HStack {
                            Text("Quality")
                            Slider(value: $quality, in: 0.3...1.0)
                            Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 42)
                        }
                    }
                    TextField("DPI (optional)", text: $dpiText)
                    Picker("Subfolder", selection: $subfolderMode) {
                        Text("None").tag("none")
                        Text("Project Name").tag("project")
                        Text("Custom").tag("custom")
                    }
                    if subfolderMode == "custom" {
                        TextField("Subfolder name", text: $subfolderName)
                    } else if subfolderMode == "project" {
                        Text("Photos go into a folder named after each photo's project (e.g. “Wedding1/”).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Rename to", text: $customName, prompt: Text("e.g. Wedding"))
                    if !customName.trimmingCharacters(in: .whitespaces).isEmpty {
                        let ext = format == .jpeg ? "jpg" : format.rawValue
                        Text("Files will be named “\(customName.trimmingCharacters(in: .whitespaces)) 001.\(ext)”, numbered in order.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Suffix", text: $nameSuffix, prompt: Text("e.g. _web"))
                    Toggle("Include EXIF/IPTC metadata", isOn: $preserveMetadata)

                    Divider()
                    Text("Watermark").font(.headline)
                    TextField("Watermark text", text: $watermarkText, prompt: Text("leave blank for none"))
                    HStack {
                        Text("Logo")
                        if let url = logoURL {
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Button("Clear") { logoPath = "" }
                        } else {
                            Text("None").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Image…") { chooseLogo() }
                    }
                    if logoURL != nil {
                        HStack {
                            Text("Logo size")
                            Slider(value: $watermarkScale, in: 0.05...0.6)
                            Text("\(Int(watermarkScale * 100))%").monospacedDigit().frame(width: 42)
                        }
                    }
                    Picker("Position", selection: positionBinding) {
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
        .frame(width: 540)
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
        if panel.runModal() == .OK, let url = panel.url { logoPath = url.path }
    }

    private func runExport() {
        guard let lib = store.library else { return }
        // What you see is what exports: persist any unsaved adjustments/brush
        // layers on the selected photo before rendering.
        if store.adjustmentsDirty, let photo = store.selectedPhoto {
            store.saveAdjustments(store.editParams, for: photo)
        }
        if store.liveLayers != nil {
            store.saveBrushLayers()
        }
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
        let position = Watermark.Position(rawValue: positionRaw) ?? .bottomCenter
        if let logo = logoURL {
            watermark = Watermark(imageURL: logo, opacity: watermarkOpacity,
                                  scale: watermarkScale, position: position)
        } else if !watermarkText.trimmingCharacters(in: .whitespaces).isEmpty {
            watermark = Watermark(text: watermarkText, opacity: watermarkOpacity, position: position)
        }
        let settings = ExportSettings(
            format: format, maxPixelSize: effectiveMaxEdge, jpegQuality: quality,
            dpi: Double(dpiText.trimmingCharacters(in: .whitespaces)), watermark: watermark,
            fileNameSuffix: nameSuffix.trimmingCharacters(in: .whitespaces),
            customName: customName.trimmingCharacters(in: .whitespaces),
            preserveMetadata: preserveMetadata,
            scalePercent: scalePercent)

        // Optional subfolder (Aperture's "Subfolder Format"): per-project or a
        // fixed custom name inside the chosen destination.
        func folder(for photo: Photo) -> URL {
            switch subfolderMode {
            case "project":
                let name = store.projects.first { $0.id == photo.version.projectUuid }?.name
                    ?? "Untitled Project"
                return dest.appendingPathComponent(sanitized(name))
            case "custom":
                let name = subfolderName.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? dest : dest.appendingPathComponent(sanitized(name))
            default:
                return dest
            }
        }
        // Resolve destinations on the main actor, then render in the
        // background with live progress (a synchronous loop beachballed).
        let targets: [(photo: Photo, folder: URL)] = photos.map { ($0, folder(for: $0)) }
        let total = targets.count
        let libRef = lib
        store.importProgress = "Exporting 1 of \(total)…"
        store.progressFraction = 0
        isPresented = false
        store.progressTask = Task.detached(priority: .userInitiated) {
            let exporter = Exporter(library: libRef)
            var failureCount = 0
            var exported = 0
            var sequencePerFolder: [String: Int] = [:]   // numbering restarts per folder
            for target in targets {
                if Task.isCancelled { break }
                let sequence = (sequencePerFolder[target.folder.path] ?? 0) + 1
                sequencePerFolder[target.folder.path] = sequence
                do {
                    _ = try exporter.export(target.photo, to: target.folder,
                                            settings: settings, sequenceIndex: sequence)
                } catch {
                    failureCount += 1
                }
                exported += 1
                let done = exported
                await MainActor.run {
                    self.store.progressFraction = Double(done) / Double(total)
                    if done < total {
                        self.store.importProgress = "Exporting \(done + 1) of \(total)…"
                    }
                }
            }
            let failures = failureCount
            let finished = exported
            let cancelled = Task.isCancelled
            await MainActor.run {
                self.store.importProgress = nil
                self.store.progressFraction = nil
                self.store.progressTask = nil
                if cancelled && finished < total {
                    self.store.errorMessage = "Export stopped — \(finished) of \(total) photo(s) were exported."
                } else if failures > 0 {
                    self.store.errorMessage = "\(failures) of \(total) photo(s) failed to export."
                }
            }
        }
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
