import Foundation
import ImageIO
import CoreGraphics

/// Decodes images with ImageIO. This handles JPEG/HEIC/TIFF/PNG **and most RAW
/// formats** (CR2, CR3, NEF, ARW, DNG…) for free, applies the embedded
/// orientation, and downsamples efficiently so we never hold a full-resolution
/// bitmap just to draw a thumbnail.
///
/// Lives in OpenLensKit (CoreGraphics/ImageIO only, no AppKit) so it stays
/// usable from the CLI, tests, and any future UI.
public enum ImageLoader {

    /// Loads a downsampled `CGImage` no larger than `maxPixelSize` on its long
    /// edge, with orientation already applied. Returns `nil` if the file can't
    /// be decoded.
    public static func cgImage(at url: URL, maxPixelSize: Int = 1024) -> CGImage? {
        let srcOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // apply orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Full-resolution decode (orientation applied). Use for export; prefer
    /// `cgImage(at:maxPixelSize:)` for on-screen thumbnails.
    public static func fullCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            // A very large cap effectively means "full size" while still
            // applying the orientation transform.
            kCGImageSourceThumbnailMaxPixelSize: 1_000_000
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Pixel dimensions of an image without decoding it.
    public static func pixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return CGSize(width: w, height: h)
    }

    /// True if ImageIO recognises the file as a decodable image.
    public static func canDecode(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return false }
        let supported = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(type as String)
    }
}
