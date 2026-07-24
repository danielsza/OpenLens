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
    private var isSelected: Bool { store.isSelected(photo.id) }

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
            .overlay(alignment: .bottomLeading) {
                if photo.master.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(4)
                }
            }

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
                    if photo.version.hasAdjustments {
                        Image(systemName: "wrench.fill").font(.system(size: 7)).foregroundStyle(Theme.captionOnDarkDim)
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
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            store.handleTap(photo,
                            command: mods.contains(.command),
                            shift: mods.contains(.shift))
        }
        .contextMenu { contextMenuItems }
        .task(id: "\(photo.id)-\(Int(size))") { await load() }
    }

    private func load() async {
        guard let lib = store.library else { return }
        image = await ImageCache.shared.image(for: photo, in: lib, maxPixel: Int(size * 2))
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Menu("Rating") {
            Button("Reject (9)") { store.setRating(-1, for: photo) }
            Button("None (0)") { store.setRating(0, for: photo) }
            ForEach(1...5, id: \.self) { n in
                Button(String(repeating: "★", count: n)) { store.setRating(n, for: photo) }
            }
        }
        Button(photo.version.isFlagged ? "Unflag" : "Flag") { store.toggleFlag(for: photo) }
        Menu("Color Label") {
            ForEach([ColorLabel.none, .red, .orange, .yellow, .green, .blue, .purple, .gray],
                    id: \.rawValue) { label in
                Button(label.displayName) { store.setColorLabel(label.rawValue, for: photo) }
            }
        }
        Divider()
        Button("Duplicate Version") { store.duplicate(photo) }
        Button("Rotate Left") {
            store.selectedPhotoID = photo.id; store.selectedPhotoIDs = [photo.id]
            store.rotateSelection(clockwise: false)
        }
        Button("Rotate Right") {
            store.selectedPhotoID = photo.id; store.selectedPhotoIDs = [photo.id]
            store.rotateSelection(clockwise: true)
        }
        Divider()
        Button("Open in External Editor") { store.openInExternalEditor(photo) }
        Button("Show in Finder") { store.showInFinder(photo) }
        Divider()
        if photo.version.isInTrash {
            Button("Put Back") { store.restoreFromTrash(photo) }
        } else {
            Button("Move to Trash") { store.moveToTrash(photo) }
        }
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

/// The horizontal filmstrip shown beneath the viewer in Split view. Hovering
/// reveals a scrubber slider for jumping anywhere in the strip (Aperture-style).
struct Filmstrip: View {
    @ObservedObject var store: LibraryStore
    @State private var hovering = false
    @State private var scrubPosition = 0.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.visiblePhotos) { photo in
                        PhotoThumbnail(store: store, photo: photo,
                                       size: store.filmstripThumbSize, showCaption: false)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)   // breathing room + scrubber space
            }
            .background(Theme.browserBackground)
            // Bookends: fade the strip out at both edges like Aperture.
            .overlay(alignment: .leading) { edgeFade(leading: true) }
            .overlay(alignment: .trailing) { edgeFade(leading: false) }
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1) }
            .overlay(alignment: .bottom) { scrubber(proxy) }
            .onHover { hovering = $0 }
            .onChange(of: store.selectedPhotoID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// Appears on hover; dragging jumps the strip anywhere in the library.
    @ViewBuilder
    private func scrubber(_ proxy: ScrollViewProxy) -> some View {
        let photos = store.visiblePhotos
        if hovering && photos.count > 8 {
            Slider(value: Binding(
                get: { scrubPosition },
                set: { value in
                    scrubPosition = value
                    let idx = Int((value * Double(photos.count - 1)).rounded())
                    proxy.scrollTo(photos[idx].id, anchor: .center)
                }
            ), in: 0...1)
            .controlSize(.mini)
            .padding(.horizontal, 26)
            .padding(.bottom, 3)
            .transition(.opacity)
            .help("Scrub through the filmstrip")
        }
    }

    private func edgeFade(leading: Bool) -> some View {
        LinearGradient(
            colors: [Theme.browserBackground, Theme.browserBackground.opacity(0)],
            startPoint: leading ? .leading : .trailing,
            endPoint: leading ? .trailing : .leading)
            .frame(width: 22)
            .allowsHitTesting(false)
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
