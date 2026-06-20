import SwiftUI
import AppKit
import OpenLensKit

/// A simple slideshow over the currently visible photos: auto-advances on a
/// timer, with play/pause, manual navigation, and an adjustable interval.
struct SlideshowView: View {
    @ObservedObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var index = 0
    @State private var image: NSImage?
    @State private var playing = true
    @State private var interval: Double = 3
    @State private var elapsed: Double = 0

    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var photos: [Photo] { store.visiblePhotos }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(20)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                Spacer()
                controls
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            index = max(0, photos.firstIndex { $0.id == store.selectedPhotoID } ?? 0)
            Task { await load() }
        }
        .onReceive(tick) { _ in
            guard playing, !photos.isEmpty else { return }
            elapsed += 0.25
            if elapsed >= interval { advance(1); elapsed = 0 }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { advance(-1) } label: { Image(systemName: "backward.fill") }
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { advance(1) } label: { Image(systemName: "forward.fill") }

            HStack(spacing: 6) {
                Image(systemName: "timer").font(.caption)
                Slider(value: $interval, in: 1...10).frame(width: 120)
                Text("\(Int(interval))s").font(.caption).monospacedDigit()
            }

            if !photos.isEmpty {
                Text("\(index + 1) / \(photos.count)").font(.caption).monospacedDigit()
            }

            Button("Done") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
        .padding(.bottom, 24)
    }

    private func advance(_ delta: Int) {
        guard !photos.isEmpty else { return }
        index = (index + delta + photos.count) % photos.count
        elapsed = 0
        Task { await load() }
    }

    private func load() async {
        guard let lib = store.library, photos.indices.contains(index) else { image = nil; return }
        image = await ImageCache.shared.fullImage(for: photos[index], in: lib)
    }
}
