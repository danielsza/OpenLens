import AppKit
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

    /// Returns a decoded, downsampled image for a photo, caching the result.
    func image(for photo: Photo, in library: ApertureLibrary, maxPixel: Int) async -> NSImage? {
        let rotation = photo.version.rotation
        let k = key("\(photo.id)#\(rotation)", maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        let url = library.displayImageURL(for: photo)
        let cg = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let base = ImageLoader.cgImage(at: url, maxPixelSize: maxPixel) else { return nil }
            return ImageLoader.rotate(base, degrees: rotation)
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
        let url = library.displayImageURL(for: photo)
        let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let base = ImageLoader.cgImage(at: url, maxPixelSize: 2400) else { return nil }
            return ImageLoader.rotate(base, degrees: rotation)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: k)
        return image
    }
}
