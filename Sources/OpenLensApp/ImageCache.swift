import AppKit
import AVFoundation
import CoreGraphics
import OpenLensKit

/// A simple in-memory image cache so scrolling a large library doesn't redecode
/// the same thumbnails repeatedly. Keyed by photo id + requested pixel size.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 800
        return c
    }()

    private func key(_ id: String, _ maxPixel: Int) -> NSString {
        "\(id)@\(maxPixel)" as NSString
    }

    /// A representative frame from a video file (~1s in).
    static func videoFrame(url: URL, maxPixel: Int) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let t = CMTime(seconds: 1, preferredTimescale: 600)
        return (try? gen.copyCGImage(at: t, actualTime: nil))
            ?? (try? gen.copyCGImage(at: .zero, actualTime: nil))
    }

    /// Returns a decoded, downsampled image for a photo, caching the result.
    func image(for photo: Photo, in library: ApertureLibrary, maxPixel: Int) async -> NSImage? {
        let rotation = photo.version.rotation
        let k = key("\(photo.id)#\(rotation)", maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        let url = library.displayImageURL(for: photo)
        let isVideo = photo.master.isVideo
        let masterURL = library.masterFileURL(for: photo.master)
        // Aperture's cached thumbnails/previews are ALREADY rotated; only the
        // raw master needs the version's rotation applied.
        let applyRotation = (url == masterURL) ? rotation : 0
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            let base: CGImage?
            if isVideo {
                // Cached thumb if Aperture made one, else grab a video frame.
                base = ImageLoader.cgImage(at: url, maxPixelSize: maxPixel)
                    ?? Self.videoFrame(url: masterURL, maxPixel: maxPixel)
            } else {
                base = ImageLoader.cgImage(at: url, maxPixelSize: maxPixel)
            }
            guard let base else { return nil }
            return ImageLoader.rotate(base, degrees: applyRotation)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: k)
        return image
    }

    /// Full-resolution decode for the viewer (cached at a high-size key).
    func fullImage(for photo: Photo, in library: ApertureLibrary) async -> NSImage? {
        let rotation = photo.version.rotation
        let k = key("\(photo.id)#\(rotation)", 0)
        if let hit = cache.object(forKey: k) { return hit }
        // Prefer Aperture's rendered preview (reflects its edits) over the master.
        let url = library.viewerImageURL(for: photo)
        // Previews/thumbnails are already rotated by Aperture; only rotate masters.
        let applyRotation = (url == library.masterFileURL(for: photo.master)) ? rotation : 0
        let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let base = ImageLoader.cgImage(at: url, maxPixelSize: 2400) else { return nil }
            return ImageLoader.rotate(base, degrees: applyRotation)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: k)
        return image
    }
}
