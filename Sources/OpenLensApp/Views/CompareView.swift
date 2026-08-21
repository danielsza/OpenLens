import SwiftUI
import AppKit
import OpenLensKit

/// Aperture-style Compare: two images side by side with synchronized zoom and
/// pan. Pinch/scroll-zoom and drag apply to both panes; double-click resets.
struct CompareView: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var left: NSImage?
    @State private var right: NSImage?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private var photos: [Photo] {
        let ids = store.selectedPhotoIDs.isEmpty
            ? [store.selectedPhotoID].compactMap { $0 }
            : Array(store.selectedPhotoIDs)
        let picked = store.visiblePhotos.filter { ids.contains($0.id) }
        return Array(picked.prefix(2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Compare").font(.headline)
                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text("Pinch or scroll to zoom · drag to pan · double-click to reset")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()

            if photos.count < 2 {
                Text("Select two photos to compare (⌘-click a second photo).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 2) {
                    pane(image: left, title: photos[0].version.name)
                    pane(image: right, title: photos[1].version.name)
                }
                .background(Color(white: 0.1))
                .gesture(magnify)
                .simultaneousGesture(drag)
                .onTapGesture(count: 2) { reset() }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { Task { await load() } }
    }

    private func pane(image: NSImage?, title: String) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack {
                    Color(white: 0.12)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(zoom)
                            .offset(offset)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            Text(title).font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4)
        }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = min(16, max(0.5, baseZoom * value)) }
            .onEnded { _ in baseZoom = zoom }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func reset() {
        zoom = 1; baseZoom = 1
        offset = .zero; baseOffset = .zero
    }

    private func load() async {
        guard let lib = store.library, photos.count == 2 else { return }
        left = await ImageCache.shared.fullImage(for: photos[0], in: lib)
        right = await ImageCache.shared.fullImage(for: photos[1], in: lib)
    }
}
