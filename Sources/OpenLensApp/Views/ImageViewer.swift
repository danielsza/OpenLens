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
        image = nil
        faces = []
        player?.pause()
        player = nil
        guard let lib = store.library, let photo = store.selectedPhoto else { return }
        if photo.id != lastPhotoID {
            lastPhotoID = photo.id
            pan = .zero; panBase = .zero
        }
        if photo.master.isVideo {
            let url = lib.masterFileURL(for: photo.master)
            if FileManager.default.fileExists(atPath: url.path) {
                player = AVPlayer(url: url)
            }
            return
        }
        image = await ImageCache.shared.fullImage(for: photo, in: lib,
                                                  adjustments: store.liveAdjustments)
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
