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

    private let loupeDiameter: CGFloat = 180
    private let loupeZoom: CGFloat = 2.5

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
            Button("") { showFaces.toggle() }
                .keyboardShortcut("f", modifiers: [])
            Button("") { store.showAdjustmentsHUD.toggle() }
                .keyboardShortcut("h", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
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

                Rectangle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
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
