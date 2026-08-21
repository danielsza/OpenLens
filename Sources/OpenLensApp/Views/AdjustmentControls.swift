import SwiftUI
import OpenLensKit

/// Aperture-style RGB histogram: red/green/blue channels overlaid additively.
struct RGBHistogramView: View {
    let histogram: ImageLoader.Histogram?

    var body: some View {
        GeometryReader { geo in
            if let h = histogram {
                let maxV = max(h.red.max() ?? 1, h.green.max() ?? 1, h.blue.max() ?? 1, 1)
                // Apple Photos style: translucent additive fills + a crisp
                // bright contour line along each channel's curve.
                ZStack {
                    channel(h.red, Color(red: 1, green: 0.15, blue: 0.15), maxV, geo.size)
                    channel(h.green, Color(red: 0.15, green: 1, blue: 0.2), maxV, geo.size)
                    channel(h.blue, Color(red: 0.25, green: 0.4, blue: 1), maxV, geo.size)
                }
                .compositingGroup()
            } else {
                Text("—").foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private func channel(_ values: [Int], _ color: Color, _ maxV: Int, _ size: CGSize) -> some View {
        let smoothed = Self.smooth(values)
        // Photos-style: subtle layered fills (NORMAL blending — additive fills
        // turned the whole plot khaki) with a crisp contour line per channel.
        fillPath(smoothed, maxV, size, closed: true)
            .fill(color.opacity(0.22))
        fillPath(smoothed, maxV, size, closed: false)
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
    }

    private func fillPath(_ smoothed: [Double], _ maxV: Int, _ size: CGSize,
                          closed: Bool) -> Path {
        Path { path in
            guard smoothed.count > 1 else { return }
            let step = size.width / CGFloat(smoothed.count - 1)
            func y(_ v: Double) -> CGFloat {
                // Power-compress peaks so a few spikes don't flatten the rest.
                let norm = pow(min(1, v / Double(maxV)), 0.6)
                return size.height * (1 - CGFloat(norm))
            }
            if closed { path.move(to: CGPoint(x: 0, y: size.height)) }
            for (i, v) in smoothed.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                if i == 0 && !closed { path.move(to: p) } else { path.addLine(to: p) }
            }
            if closed {
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
        }
    }

    /// 5-tap weighted moving average — smooths bucket noise into clean curves.
    private static func smooth(_ values: [Int]) -> [Double] {
        guard values.count > 4 else { return values.map(Double.init) }
        let w: [Double] = [1, 2, 3, 2, 1]
        return values.indices.map { i in
            var total = 0.0, weight = 0.0
            for (k, wk) in w.enumerated() {
                let j = i + k - 2
                guard values.indices.contains(j) else { continue }
                total += Double(values[j]) * wk
                weight += wk
            }
            return total / max(weight, 1)
        }
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
            brick("Geometry") {
                slider("Straighten", \.straighten, -15...15)
                if store.editParams.hasCrop {
                    HStack {
                        Text(String(format: "Crop %.0f × %.0f",
                                    store.editParams.cropWidth, store.editParams.cropHeight))
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            store.editParams.cropX = 0; store.editParams.cropY = 0
                            store.editParams.cropWidth = 0; store.editParams.cropHeight = 0
                            store.previewAdjustments(store.editParams)
                        }
                        .controlSize(.mini)
                    }
                }
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
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Saving is off — edits won't persist.")
                        .font(.caption)
                    Spacer()
                    Button("Enable") { store.writesEnabled = true }
                        .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange.opacity(0.5)))
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
