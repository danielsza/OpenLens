import SwiftUI
import OpenLensKit

/// The control strip (Aperture-style): rating/flag/labels centered and
/// prominent, photo name at the left, HUD + thumbnail-size at the right.
/// In Split view it sits directly under the viewer, above the filmstrip.
struct ControlBar: View {
    @ObservedObject var store: LibraryStore
    /// Inline hover hint (macOS tooltips proved unreliable here).
    @State private var hint: String?

    var body: some View {
        ZStack {
            // Edges: name (left), HUD + size slider (right).
            HStack(spacing: 12) {
                if let photo = store.selectedPhoto {
                    Text(photo.version.name)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No selection")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Button {
                    store.toggleAdjustmentsHUD()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(store.showAdjustmentsHUD ? Color.accentColor : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Adjustments HUD (H)")
                .onHover { hint = $0 ? "Adjustments HUD (H)" : nil }

                Button {
                    store.toggleBrushMode()
                } label: {
                    Image(systemName: "paintbrush.pointed")
                        .foregroundStyle(store.brushMode ? Color.accentColor : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Brush local adjustments (P)")
                .onHover { hint = $0 ? "Brush — paint local adjustments (P)" : nil }

                Button {
                    store.toggleCropMode()
                } label: {
                    Image(systemName: "crop")
                        .foregroundStyle(store.cropMode ? Color.accentColor : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Crop (C)")
                .onHover { hint = $0 ? "Crop — drag a rectangle on the photo (C)" : nil }

                if store.viewerFocused && store.selectedPhoto != nil {
                    // Viewer is focused: the slider zooms the big image.
                    HStack(spacing: 6) {
                        Image(systemName: "minus.magnifyingglass").font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                        Slider(value: $store.viewerZoom, in: 1...8)
                            .frame(width: 120)
                            .help("Zoom the selected image (double-click image to reset)")
                        Image(systemName: "plus.magnifyingglass").font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                    .onHover { hint = $0 ? "Zoom the photo (double-click to reset)" : nil }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "photo").font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                        Slider(value: $store.thumbnailSize, in: 90...320)
                            .frame(width: 120)
                            .help("Thumbnail size (grid and filmstrip) — click the big image to zoom it instead")
                        Image(systemName: "photo").font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .onHover { hint = $0 ? "Thumbnail size — click the photo to zoom instead" : nil }
                }
            }

            // Center: the rating cluster, bigger, like Aperture.
            if let photo = store.selectedPhoto {
                HStack(spacing: 14) {
                    Button {
                        store.setRatingForSelection(photo.version.rating < 0 ? 0 : -1)
                    } label: {
                        Image(systemName: photo.version.rating < 0 ? "xmark.circle.fill" : "xmark.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(photo.version.rating < 0 ? .red : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reject (9)")

                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= photo.version.rating ? "star.fill" : "star")
                                .font(.system(size: 15))
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
                            .font(.system(size: 14))
                            .foregroundStyle(photo.version.isFlagged ? .orange : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Flag (/)")

                    Divider().frame(height: 16)

                    HStack(spacing: 6) {
                        ForEach([ColorLabel.none, .red, .orange, .yellow, .green, .blue, .purple, .gray],
                                id: \.rawValue) { label in
                            let dotColor = ColorLabelStyle.color(label.rawValue)
                            Circle()
                                .fill(dotColor ?? Color.clear)
                                .overlay(Circle().strokeBorder(Theme.textSecondary,
                                                               lineWidth: dotColor == nil ? 1 : 0))
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Circle().strokeBorder(.white,
                                        lineWidth: photo.version.colorLabel == label.rawValue ? 2 : 0)
                                )
                                .onTapGesture { store.setColorLabelForSelection(label.rawValue) }
                                .help(label.displayName)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.panel)
    }
}
