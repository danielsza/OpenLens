import SwiftUI

/// Aperture-inspired dark palette. Aperture used a near-black charcoal UI so
/// photos pop; these greys approximate it.
enum Theme {
    /// Aperture's chrome was a medium light-grey (toolbars, sidebar, inspector,
    /// control bar). The photo browser/viewer area is a darker neutral grey.
    static let chrome = Color(white: 0.62)
    static let appBackground = Color(white: 0.62)
    static let panel = Color(white: 0.62)
    static let panelRaised = Color(white: 0.66)
    /// Dark neutral grey behind photos (viewer + browser + filmstrip).
    static let viewerBackground = Color(white: 0.40)
    static let browserBackground = Color(white: 0.43)
    static let hairline = Color.black.opacity(0.18)
    /// Selected thumbnails get a bright border, as in Aperture.
    static let selection = Color.white
    /// Text on the light chrome (dark).
    static let textPrimary = Color(white: 0.12)
    static let textSecondary = Color(white: 0.32)
    /// Text/captions over the dark photo area (light).
    static let captionOnDark = Color.white.opacity(0.85)
    static let captionOnDarkDim = Color.white.opacity(0.45)
}

/// The three browser layouts, matching Aperture's view modes.
enum ViewMode: String, CaseIterable, Identifiable {
    case grid, split, viewer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: return "Grid"
        case .split: return "Split"
        case .viewer: return "Viewer"
        }
    }
    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .split: return "rectangle.split.1x2"
        case .viewer: return "rectangle"
        }
    }
}
