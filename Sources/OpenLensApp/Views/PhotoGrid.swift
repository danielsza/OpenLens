import SwiftUI
import AppKit
import CoreGraphics
import OpenLensKit

struct PhotoGrid: View {
    @ObservedObject var store: LibraryStore

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
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
        }
        .navigationTitle(currentProjectName)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Rating", selection: $store.filter.minRating) {
                Text("All").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)★+").tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 110)

            Toggle("Flagged", isOn: $store.filter.flaggedOnly)
                .toggleStyle(.button)

            Toggle("Edited", isOn: $store.filter.adjustedOnly)
                .toggleStyle(.button)

            TextField("Filter by name", text: $store.filter.nameContains)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Spacer()
            Text("\(store.visiblePhotos.count) photos")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        // Prefer Aperture's cached thumbnail; fall back to the master. ImageIO
        // decodes RAW + applies orientation, and downsamples for the grid.
        let url = library.displayImageURL(for: photo)
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            ImageLoader.cgImage(at: url, maxPixelSize: 320)
        }.value
        if let cg {
            self.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }
}
