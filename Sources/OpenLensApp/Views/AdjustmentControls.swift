import SwiftUI
import OpenLensKit

/// Aperture-style RGB histogram: red/green/blue channels overlaid additively.
struct RGBHistogramView: View {
    let histogram: ImageLoader.Histogram?

    var body: some View {
        GeometryReader { geo in
            if let h = histogram {
                let maxV = max(h.red.max() ?? 1, h.green.max() ?? 1, h.blue.max() ?? 1, 1)
                ZStack {
                    channel(h.red, Color(red: 0.95, green: 0.2, blue: 0.2), maxV, geo.size)
                    channel(h.green, Color(red: 0.2, green: 0.9, blue: 0.3), maxV, geo.size)
                    channel(h.blue, Color(red: 0.25, green: 0.45, blue: 1.0), maxV, geo.size)
                }
                .blendMode(.screen)
            } else {
                Text("—").foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.35)))
    }

    private func channel(_ values: [Int], _ color: Color, _ maxV: Int, _ size: CGSize) -> some View {
        Path { path in
            guard !values.isEmpty else { return }
            let step = size.width / CGFloat(values.count)
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in values.enumerated() {
                let y = size.height * (1 - CGFloat(v) / CGFloat(maxV))
                path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        .fill(color.opacity(0.65))
    }
}

/// The adjustment "bricks" (White Balance / Exposure / Enhance / Highlights &
/// Shadows / Sharpen), shared by the inspector tab and the floating HUD.
struct AdjustmentControls: View {
    @ObservedObject var store: LibraryStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            brick("White Balance") {
                slider("Temp", \.temperature, -100...100)
                slider("Tint", \.tint, -100...100)
            }
            brick("Exposure") {
                slider("Exposure", \.exposure, -2...2)
            }
            brick("Enhance") {
                slider("Contrast", \.contrast, 0.5...1.5)
                slider("Saturation", \.saturation, 0...2)
            }
            brick("Highlights & Shadows") {
                slider("Highlights", \.highlights, -1...1)
                slider("Shadows", \.shadows, -1...1)
            }
            brick("Sharpen") {
                slider("Sharpness", \.sharpness, 0...1)
            }

            HStack {
                Button("Reset") {
                    store.editParams = OLAdjustments()
                    store.previewAdjustments(store.editParams)
                }
                .disabled(store.editParams.isIdentity && store.savedEditParams.isIdentity)
                Spacer()
                Button("Save") {
                    if let photo = store.selectedPhoto {
                        store.saveAdjustments(store.editParams, for: photo)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!store.adjustmentsDirty)
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .small : .regular)
            }
            if !store.writesEnabled && store.adjustmentsDirty {
                Text("Turn on “Save edits” in the toolbar to persist.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func brick<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(compact ? .caption2.bold() : .caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.12)))
    }

    private func slider(_ label: String,
                        _ keyPath: WritableKeyPath<OLAdjustments, Double>,
                        _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .frame(width: compact ? 54 : 62, alignment: .leading)
            Slider(value: Binding(
                get: { store.editParams[keyPath: keyPath] },
                set: { store.editParams[keyPath: keyPath] = $0
                       store.previewAdjustments(store.editParams) }
            ), in: range)
            .controlSize(.mini)
            Text(String(format: "%.2f", store.editParams[keyPath: keyPath]))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
