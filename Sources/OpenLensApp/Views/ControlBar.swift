import SwiftUI
import OpenLensKit

/// The bottom control bar (Aperture had ratings, flag, colour labels and a
/// thumbnail-size slider along the bottom).
struct ControlBar: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        HStack(spacing: 16) {
            if let photo = store.selectedPhoto {
                // Reject (rating -1)
                Button {
                    store.setRatingForSelection(photo.version.rating < 0 ? 0 : -1)
                } label: {
                    Image(systemName: photo.version.rating < 0 ? "xmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(photo.version.rating < 0 ? .red : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Reject")

                // Rating
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                            .foregroundStyle(star <= photo.version.rating ? .yellow : Theme.textSecondary)
                            .onTapGesture {
                                store.setRatingForSelection(photo.version.rating == star ? 0 : star)
                            }
                    }
                }

                Button {
                    store.setFlagForSelection(!photo.version.isFlagged)
                } label: {
                    Image(systemName: photo.version.isFlagged ? "flag.fill" : "flag")
                        .foregroundStyle(photo.version.isFlagged ? .orange : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Flag")

                // Colour labels
                HStack(spacing: 5) {
                    ForEach([ColorLabel.none, .red, .orange, .yellow, .green, .blue, .purple, .gray], id: \.rawValue) { label in
                        let dotColor = ColorLabelStyle.color(label.rawValue)
                        Circle()
                            .fill(dotColor ?? Color.clear)
                            .overlay(Circle().strokeBorder(Theme.textSecondary,
                                                           lineWidth: dotColor == nil ? 1 : 0))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().strokeBorder(.white,
                                    lineWidth: photo.version.colorLabel == label.rawValue ? 2 : 0)
                            )
                            .onTapGesture { store.setColorLabelForSelection(label.rawValue) }
                            .help(label.displayName)
                    }
                }

                Text(photo.version.name)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No selection").foregroundStyle(Theme.textSecondary).font(.caption)
            }

            Spacer()

            // Thumbnail size
            Image(systemName: "photo").font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
            Slider(value: $store.thumbnailSize, in: 90...320).frame(width: 130)
            Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }
}
