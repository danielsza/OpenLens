import SwiftUI
import AppKit
import OpenLensKit

struct PhotoGrid: View {
    @ObservedObject var store: LibraryStore

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.visiblePhotos) { photo in
                    Thumbnail(photo: photo,
                              library: store.library,
                              isSelected: photo.id == store.selectedPhotoID)
                        .onTapGesture { store.selectedPhotoID = photo.id }
                }
            }
            .padding(12)
        }
        .navigationTitle(currentProjectName)
    }

    private var currentProjectName: String {
        store.projects.first { $0.id == store.selectedProjectID }?.name ?? "All Photos"
    }
}

struct Thumbnail: View {
    let photo: Photo
    let library: ApertureLibrary?
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundStyle(star <= photo.version.rating ? .yellow : .secondary)
                }
                if photo.version.isFlagged {
                    Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(.orange)
                }
            }
            Text(photo.version.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .task(id: photo.id) { await loadImage() }
    }

    private func loadImage() async {
        guard let library else { return }
        let url = library.masterFileURL(for: photo.master)
        let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
            // For the scaffold we load the master file directly. RAW files and
            // rendered previews/thumbnails are handled later via ImageIO.
            NSImage(contentsOf: url)
        }.value
        await MainActor.run { self.image = loaded }
    }
}
