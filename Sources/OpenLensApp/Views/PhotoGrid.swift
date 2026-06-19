import SwiftUI
import AppKit
import OpenLensKit

/// A single thumbnail cell, shared by the grid and the filmstrip.
struct PhotoThumbnail: View {
    @ObservedObject var store: LibraryStore
    let photo: Photo
    var size: CGFloat = 150
    var showCaption: Bool = true

    @State private var image: NSImage?
    private var isSelected: Bool { photo.id == store.selectedPhotoID }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Theme.viewerBackground)
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: size, height: size * 0.72)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Theme.selection : Theme.hairline,
                                  lineWidth: isSelected ? 3 : 1)
            )

            if showCaption {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                            .font(.system(size: 7))
                            .foregroundStyle(star <= photo.version.rating ? .yellow : Theme.captionOnDarkDim)
                    }
                    if photo.version.isFlagged {
                        Image(systemName: "flag.fill").font(.system(size: 7)).foregroundStyle(.orange)
                    }
                    if let c = ColorLabelStyle.color(photo.version.colorLabel) {
                        Circle().fill(c).frame(width: 6, height: 6)
                    }
                }
                Text(photo.version.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white : Theme.captionOnDark)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedPhotoID = photo.id }
        .task(id: "\(photo.id)-\(Int(size))") { await load() }
    }

    private func load() async {
        guard let lib = store.library else { return }
        image = await ImageCache.shared.image(for: photo, in: lib, maxPixel: Int(size * 2))
    }
}

/// The grid browser (Aperture's "Browser" view).
struct GridBrowser: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: store.thumbnailSize + 20), spacing: 14)],
                      spacing: 14) {
                ForEach(store.visiblePhotos) { photo in
                    PhotoThumbnail(store: store, photo: photo, size: store.thumbnailSize)
                }
            }
            .padding(16)
        }
        .background(Theme.browserBackground)
    }
}

/// The horizontal filmstrip shown beneath the viewer in Split view.
struct Filmstrip: View {
    @ObservedObject var store: LibraryStore
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.visiblePhotos) { photo in
                        PhotoThumbnail(store: store, photo: photo, size: 96, showCaption: false)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Theme.browserBackground)
            .onChange(of: store.selectedPhotoID) { id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// Colour-label palette matching Aperture's `colorLabelIndex`.
enum ColorLabelStyle {
    static func color(_ index: Int) -> Color? {
        switch ColorLabel(rawValue: index) ?? .none {
        case .none: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}
