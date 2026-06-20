import SwiftUI
import AppKit
import OpenLensKit

/// A freeform arrangement canvas, like Aperture's Light Table: drag photos
/// anywhere, resize the whole set, and auto-arrange into a grid.
struct LightTableView: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var positions: [String: CGPoint] = [:]
    @State private var dragStart: [String: CGPoint] = [:]
    @State private var tileWidth: CGFloat = 180

    private var photos: [Photo] {
        let sel = store.selectedPhotoIDs
        let base = sel.isEmpty ? store.visiblePhotos : store.visiblePhotos.filter { sel.contains($0.id) }
        return base.isEmpty ? store.visiblePhotos : base
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                ZStack {
                    Color(white: 0.16)
                    ForEach(photos) { photo in
                        LightTableTile(store: store, photo: photo, width: tileWidth)
                            .position(positions[photo.id] ?? .zero)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let base = dragStart[photo.id] ?? positions[photo.id] ?? .zero
                                        if dragStart[photo.id] == nil { dragStart[photo.id] = base }
                                        positions[photo.id] = CGPoint(x: base.x + value.translation.width,
                                                                      y: base.y + value.translation.height)
                                    }
                                    .onEnded { _ in dragStart[photo.id] = nil }
                            )
                    }
                }
                .onAppear { if positions.isEmpty { arrange(in: geo.size) } }
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("Light Table").font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "photo").font(.caption)
                Slider(value: $tileWidth, in: 100...360).frame(width: 140)
            }
            Button("Arrange") { arrangeUsingDefaultSize() }
            Button("Done") { isPresented = false }.keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    private func arrangeUsingDefaultSize() {
        arrange(in: CGSize(width: 1000, height: 700))
    }

    private func arrange(in size: CGSize) {
        let cols = max(1, Int(size.width / (tileWidth + 24)))
        let stepX = tileWidth + 24
        let stepY = tileWidth * 0.75 + 36
        for (i, photo) in photos.enumerated() {
            let r = i / cols, c = i % cols
            positions[photo.id] = CGPoint(x: CGFloat(c) * stepX + tileWidth / 2 + 24,
                                          y: CGFloat(r) * stepY + tileWidth * 0.4 + 24)
        }
    }
}

private struct LightTableTile: View {
    @ObservedObject var store: LibraryStore
    let photo: Photo
    let width: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4))
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: width, height: width * 0.75)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.15)))
        .shadow(radius: 4)
        .task(id: "\(photo.id)-\(Int(width))") {
            if let lib = store.library {
                image = await ImageCache.shared.image(for: photo, in: lib, maxPixel: Int(width * 2))
            }
        }
    }
}
