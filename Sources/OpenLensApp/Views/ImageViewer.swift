import SwiftUI
import AppKit
import OpenLensKit

/// The large image viewer (Aperture's "Viewer"). Shows the selected photo on a
/// near-black background.
struct ImageViewer: View {
    @ObservedObject var store: LibraryStore
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.viewerBackground
            if store.selectedPhoto != nil {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    ProgressView()
                }
            } else {
                Text("Select a photo")
                    .foregroundStyle(Theme.captionOnDark)
            }
        }
        .task(id: store.selectedPhotoID) { await load() }
    }

    private func load() async {
        image = nil
        guard let lib = store.library, let photo = store.selectedPhoto else { return }
        image = await ImageCache.shared.fullImage(for: photo, in: lib)
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
