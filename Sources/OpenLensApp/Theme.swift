import SwiftUI

/// Aperture-inspired dark palette. Aperture used a near-black charcoal UI so
/// photos pop; these greys approximate it.
enum Theme {
    static let appBackground = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let viewerBackground = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let panel = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let panelRaised = Color(red: 0.19, green: 0.19, blue: 0.20)
    static let hairline = Color.white.opacity(0.08)
    static let selection = Color.accentColor
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
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
