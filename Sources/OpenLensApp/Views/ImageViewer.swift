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
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .task(id: store.selectedPhotoID) { await load() }
    }

    private func load() async {
        image = nil
        guard let lib = store.library, let photo = store.selectedPhoto else { return }
        image = await ImageCache.shared.fullImage(for: photo, in: lib)
    }
}
