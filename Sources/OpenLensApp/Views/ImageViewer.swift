import SwiftUI
import AppKit
import AVKit
import OpenLensKit

/// The large image viewer (Aperture's "Viewer"). Shows the selected photo on a
/// near-black background, with an optional Loupe magnifier (` key).
struct ImageViewer: View {
    @ObservedObject var store: LibraryStore
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var loupeEnabled = false
    @State private var showFaces = false
    @State private var faces: [DetectedFace] = []
    @State private var hover: CGPoint?
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var lastPhotoID: String?
    /// In-progress brush stroke, in fitted-rect-local view coordinates.
    @State private var currentStroke: [CGPoint] = []
    /// Crop-drag state (fitted-rect-local view coordinates).
    @State private var cropDragStart: CGPoint?
    @State private var cropDraft: CGRect?

    private let loupeDiameter: CGFloat = 180
    /// Aperture offered 50%–1600%; step through with = / - while the loupe is on.
    @State private var loupeZoom: CGFloat = 2.5
    private let loupeZoomLevels: [CGFloat] = [0.5, 1, 1.5, 2.5, 4, 8, 16]

    var body: some View {
        ZStack {
            Theme.viewerBackground
            if store.selectedPhoto != nil {
                if let player {
                    VideoPlayer(player: player)
                        .padding(16)
                } else if let image {
                    viewerBody(image)
                } else {
                    ProgressView()
                }
            } else {
                Text("Select a photo")
                    .foregroundStyle(Theme.captionOnDark)
            }
        }
        .task(id: "\(store.selectedPhotoID ?? "none")#\(store.adjustmentsRevision)") { await load() }
        .background(loupeShortcut)
    }

    private var loupeShortcut: some View {
        Group {
            Button("") { loupeEnabled.toggle() }
                .keyboardShortcut("`", modifiers: [])
            // "b" = face Boxes ("f" is full-screen mode, like Aperture).
            Button("") { showFaces.toggle() }
                .keyboardShortcut("b", modifiers: [])
            Button("") { store.showAdjustmentsHUD.toggle() }
                .keyboardShortcut("h", modifiers: [])
            Button("") { stepLoupeZoom(1) }
                .keyboardShortcut("=", modifiers: [])
            Button("") { stepLoupeZoom(-1) }
                .keyboardShortcut("-", modifiers: [])
            Button("") { store.toggleBrushMode() }
                .keyboardShortcut("p", modifiers: [])
            Button("") { store.toggleCropMode() }
                .keyboardShortcut("c", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func stepLoupeZoom(_ direction: Int) {
        guard loupeEnabled else { return }
        let idx = loupeZoomLevels.firstIndex { $0 >= loupeZoom } ?? 3
        let next = max(0, min(loupeZoomLevels.count - 1, idx + direction))
        loupeZoom = loupeZoomLevels[next]
    }

    // MARK: - Crop

    /// Drag-to-crop overlay: dims outside the draft rect, thirds grid inside,
    /// Apply/Cancel buttons underneath.
    @ViewBuilder
    private func cropLayer(fitted: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Dim everything outside the draft (even-odd fill).
            Path { p in
                p.addRect(CGRect(origin: .zero, size: fitted.size))
                if let r = cropDraft { p.addRect(r) }
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            if let r = cropDraft {
                Path { p in
                    p.addRect(r)
                    // Thirds grid.
                    for i in 1...2 {
                        let x = r.minX + r.width * CGFloat(i) / 3
                        p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                        let y = r.minY + r.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
            } else {
                Text("Drag to select the crop area")
                    .font(.caption).foregroundStyle(.white)
                    .padding(6).background(.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = cropDragStart ?? value.startLocation
                    cropDragStart = start
                    cropDraft = CGRect(x: min(start.x, value.location.x),
                                       y: min(start.y, value.location.y),
                                       width: abs(value.location.x - start.x),
                                       height: abs(value.location.y - start.y))
                }
                .onEnded { _ in cropDragStart = nil }
        )
        .position(x: fitted.midX, y: fitted.midY)
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Button("Cancel") { exitCropMode() }
                Button("Apply Crop") { applyCrop(fitted: fitted) }
                    .buttonStyle(.borderedProminent)
                    .disabled(cropDraft == nil || (cropDraft?.width ?? 0) < 8)
            }
            .controlSize(.small)
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 26)
            .environment(\.colorScheme, .dark)
        }
    }

    private func applyCrop(fitted: CGRect) {
        guard let r = cropDraft, let photo = store.selectedPhoto,
              fitted.width > 0, fitted.height > 0 else { return }
        let mw = Double(photo.version.masterWidth ?? Int(image?.size.width ?? fitted.width))
        let mh = Double(photo.version.masterHeight ?? Int(image?.size.height ?? fitted.height))
        // View-local top-left rect → master pixels, bottom-left origin.
        store.editParams.cropX = Double(r.minX / fitted.width) * mw
        store.editParams.cropY = mh - Double(r.maxY / fitted.height) * mh
        store.editParams.cropWidth = Double(r.width / fitted.width) * mw
        store.editParams.cropHeight = Double(r.height / fitted.height) * mh
        store.previewAdjustments(store.editParams)
        exitCropMode()
    }

    private func exitCropMode() {
        cropDraft = nil
        cropDragStart = nil
        store.cropMode = false
    }

    // MARK: - Brush

    private func brushViewScale(_ fitted: CGRect) -> Double {
        guard let photo = store.selectedPhoto else { return 1 }
        let mw = Double(photo.version.masterWidth ?? Int(image?.size.width ?? fitted.width))
        return mw > 0 ? fitted.width / mw : 1
    }

    /// Transparent layer over the photo that captures paint strokes.
    @ViewBuilder
    private func brushPaintLayer(fitted: CGRect) -> some View {
        let scale = brushViewScale(fitted)
        ZStack(alignment: .topLeading) {
            Color.clear
            if currentStroke.count > 1 {
                Path { p in p.addLines(currentStroke) }
                    .stroke(Color.white.opacity(store.brushErase ? 0.15 : 0.35),
                            style: StrokeStyle(lineWidth: max(2, 2 * store.brushRadius * scale),
                                               lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                hover = CGPoint(x: p.x + fitted.minX, y: p.y + fitted.minY)
            case .ended:
                hover = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in currentStroke.append(value.location) }
                .onEnded { _ in commitStroke(fitted: fitted) }
        )
        .position(x: fitted.midX, y: fitted.midY)
    }

    private func commitStroke(fitted: CGRect) {
        defer { currentStroke = [] }
        guard !currentStroke.isEmpty, let photo = store.selectedPhoto else { return }
        let mw = Double(photo.version.masterWidth ?? Int(image?.size.width ?? fitted.width))
        let mh = Double(photo.version.masterHeight ?? Int(image?.size.height ?? fitted.height))
        guard mw > 0, mh > 0, fitted.width > 0, fitted.height > 0 else { return }
        // View-local (top-left origin) → master pixels (bottom-left origin).
        let points = currentStroke.map { p in
            OLBrushPoint(x: Double(p.x / fitted.width) * mw,
                         y: mh - Double(p.y / fitted.height) * mh)
        }
        store.addBrushStroke(OLBrushStroke(points: points,
                                           radius: store.brushRadius,
                                           softness: store.brushSoftness,
                                           flow: 1,
                                           erase: store.brushErase))
    }

    /// Floating brush controls (radius/softness/erase + the layer's effect).
    private var brushHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Brush", systemImage: "paintbrush.pointed")
                    .font(.caption.bold())
                Spacer()
                Button { store.toggleBrushMode() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            brushSlider("Radius", value: $store.brushRadius, in: 10...300)
            brushSlider("Softness", value: $store.brushSoftness, in: 0...1)
            Toggle("Erase", isOn: $store.brushErase)
                .font(.caption2).toggleStyle(.checkbox)

            Divider()
            Text("Effect").font(.caption2.bold()).foregroundStyle(.secondary)
            effectSlider("Exposure", \.exposure, -2...2)
            effectSlider("Saturation", \.saturation, 0...2)
            effectSlider("Sharpness", \.sharpness, 0...1)

            HStack {
                Button("Clear") { store.clearBrushLayers() }.controlSize(.small)
                Spacer()
                Button("Save") { store.saveBrushLayers() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Text("Paint on the photo to apply the effect locally.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
        .shadow(radius: 10)
        .environment(\.colorScheme, .dark)
    }

    private func brushSlider(_ label: String, value: Binding<Double>,
                             in range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).frame(width: 56, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini)
        }
    }

    private func effectSlider(_ label: String,
                              _ keyPath: WritableKeyPath<OLAdjustments, Double>,
                              _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).frame(width: 56, alignment: .leading)
            Slider(value: Binding(
                get: { store.brushParams[keyPath: keyPath] },
                set: { store.brushParams[keyPath: keyPath] = $0
                       store.brushParamsChanged() }
            ), in: range)
            .controlSize(.mini)
            Text(String(format: "%.2f", store.brushParams[keyPath: keyPath]))
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// Aperture-style floating Adjustments HUD.
    private var adjustmentsHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Adjustments", systemImage: "slider.horizontal.3")
                    .font(.caption.bold())
                Spacer()
                Button {
                    store.showAdjustmentsHUD = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            AdjustmentControls(store: store, compact: true)
        }
        .padding(10)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
        .shadow(radius: 10)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func viewerBody(_ image: NSImage) -> some View {
        if store.viewerZoom > 1.01 {
            zoomedBody(image)
        } else {
            fitBody(image)
        }
    }

    /// Zoomed-in view: drag to pan, double-click to reset to fit.
    private func zoomedBody(_ image: NSImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(store.viewerZoom)
                    .offset(pan)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        pan = CGSize(width: panBase.width + value.translation.width,
                                     height: panBase.height + value.translation.height)
                    }
                    .onEnded { _ in panBase = pan }
            )
            .onTapGesture(count: 2) {
                store.viewerZoom = 1
                pan = .zero; panBase = .zero
            }
            .overlay(alignment: .topTrailing) {
                Text(String(format: "%.0f%%", store.viewerZoom * 100))
                    .font(.caption2).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func fitBody(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let fitted = fittedRect(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                // Aperture-style bookend: soft shadow + hairline frame around
                // the photo itself.
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: fitted.width + 6, height: fitted.height + 6)
                    .position(x: fitted.midX + 2, y: fitted.midY + 3)
                    .blur(radius: 6)
                    .allowsHitTesting(false)

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hover = p
                        case .ended: hover = nil
                        }
                    }
                    .onTapGesture {
                        // Focus the viewer: the size slider now zooms this image.
                        store.viewerFocused = true
                    }

                Rectangle()
                    .strokeBorder(store.viewerFocused ? Color.accentColor.opacity(0.8)
                                                      : Color.white.opacity(0.18),
                                  lineWidth: store.viewerFocused ? 2 : 1)
                    .frame(width: fitted.width + 2, height: fitted.height + 2)
                    .position(x: fitted.midX, y: fitted.midY)
                    .allowsHitTesting(false)

                if store.cropMode {
                    cropLayer(fitted: fitted)
                }

                if store.brushMode {
                    brushPaintLayer(fitted: fitted)
                    if let p = hover {
                        let d = max(6, 2 * store.brushRadius * brushViewScale(fitted))
                        Circle()
                            .stroke(store.brushErase ? Color.red.opacity(0.8)
                                                     : Color.white.opacity(0.8), lineWidth: 1.5)
                            .frame(width: d, height: d)
                            .position(p)
                            .allowsHitTesting(false)
                    }
                }

                if showFaces {
                    ForEach(faces) { face in
                        let r = CGRect(x: fitted.minX + face.rect.minX * fitted.width,
                                       y: fitted.minY + face.rect.minY * fitted.height,
                                       width: face.rect.width * fitted.width,
                                       height: face.rect.height * fitted.height)
                        ZStack(alignment: .bottom) {
                            Rectangle().strokeBorder(.yellow.opacity(0.9), lineWidth: 2)
                            if let name = face.name {
                                Text(name).font(.caption2).padding(.horizontal, 4)
                                    .background(.yellow.opacity(0.85), in: Capsule())
                                    .foregroundStyle(.black)
                                    .offset(y: 14)
                            }
                        }
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                    }
                }

                if loupeEnabled, let p = hover, fitted.contains(p) {
                    loupe(image, fitted: fitted, at: p)
                }

                if store.showAdjustmentsHUD {
                    adjustmentsHUD
                        .position(x: geo.size.width - 160, y: min(geo.size.height - 220, 260))
                }
                if store.brushMode {
                    brushHUD
                        .position(x: 140, y: max(200, geo.size.height - 200))
                }
            }
        }
        .padding(16)
    }

    /// A circular magnifier centred on the cursor showing a zoomed crop.
    private func loupe(_ image: NSImage, fitted: CGRect, at p: CGPoint) -> some View {
        let d = loupeDiameter, z = loupeZoom
        // Where the hovered point lands in the zoomed image, so we can offset
        // the zoomed image to put that point at the loupe's centre.
        let zx = (p.x - fitted.minX) * z
        let zy = (p.y - fitted.minY) * z
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: fitted.width * z, height: fitted.height * z)
                .offset(x: d / 2 - zx, y: d / 2 - zy)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
        .overlay(alignment: .bottom) {
            Text(String(format: "%.0f%%", loupeZoom * 100))
                .font(.caption2).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(.black.opacity(0.7), in: Capsule())
                .foregroundStyle(.white)
                .offset(y: 10)
        }
        .shadow(radius: 6)
        .position(p)
        .allowsHitTesting(false)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func load() async {
        guard let lib = store.library, let photo = store.selectedPhoto else {
            image = nil; faces = []
            player?.pause(); player = nil
            lastPhotoID = nil
            return
        }
        // Only blank the canvas when the PHOTO changes — for slider tweaks
        // the previous frame stays up until the new render is ready, so
        // adjustments feel live instead of "reloading".
        let photoChanged = photo.id != lastPhotoID
        if photoChanged {
            lastPhotoID = photo.id
            image = nil
            faces = []
            player?.pause(); player = nil
            pan = .zero; panBase = .zero
        }
        if photo.master.isVideo {
            if photoChanged {
                let url = lib.masterFileURL(for: photo.master)
                if FileManager.default.fileExists(atPath: url.path) {
                    player = AVPlayer(url: url)
                }
            }
            return
        }
        image = await ImageCache.shared.fullImage(for: photo, in: lib,
                                                  adjustments: store.liveAdjustments,
                                                  layersOverride: store.liveLayers)
        faces = lib.detectedFaces(for: photo)
        // Prefetch neighbours so arrow-key browsing feels instant.
        let photos = store.visiblePhotos
        if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
            for offset in [1, -1] {
                let n = idx + offset
                guard photos.indices.contains(n) else { continue }
                let neighbour = photos[n]
                Task.detached(priority: .background) {
                    _ = await ImageCache.shared.fullImage(for: neighbour, in: lib)
                }
            }
        }
    }
}
