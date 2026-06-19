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

    /// Writes a downsampled JPEG thumbnail of `src` to `dest`. Returns the
    /// thumbnail's pixel size, or nil on failure. The destination directory
    /// must already exist.
    @discardableResult
    public static func writeJPEGThumbnail(from src: URL, to dest: URL,
                                          maxPixel: Int = 1024, quality: Double = 0.85) -> CGSize? {
        guard let cg = cgImage(at: src, maxPixelSize: maxPixel),
              let out = CGImageDestinationCreateWithURL(dest as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(out, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { return nil }
        return CGSize(width: cg.width, height: cg.height)
    }

    /// Extracts EXIF/TIFF metadata into the key names OpenLens stores in
    /// `.apversion` `exifProperties` (Make, Model, LensModel, ISOSpeedRating,
    /// ShutterSpeed, FNumber, FocalLength, PixelWidth/Height, ColorModel).
    public static func exifSummary(at url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        var out: [String: Any] = [:]
        if let w = props[kCGImagePropertyPixelWidth] as? Int { out["PixelWidth"] = w }
        if let h = props[kCGImagePropertyPixelHeight] as? Int { out["PixelHeight"] = h }
        if let cm = props[kCGImagePropertyColorModel] as? String { out["ColorModel"] = cm }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let mk = tiff[kCGImagePropertyTIFFMake] as? String { out["Make"] = mk }
            if let md = tiff[kCGImagePropertyTIFFModel] as? String { out["Model"] = md }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { out["ISOSpeedRating"] = iso }
            if let et = exif[kCGImagePropertyExifExposureTime] as? Double { out["ShutterSpeed"] = et }
            if let fn = exif[kCGImagePropertyExifFNumber] as? Double { out["FNumber"] = fn }
            if let fl = exif[kCGImagePropertyExifFocalLength] as? Double { out["FocalLength"] = fl }
            if let lm = exif[kCGImagePropertyExifLensModel] as? String { out["LensModel"] = lm }
        }
        return out
    }

    /// True if ImageIO recognises the file as a decodable image.
    public static func canDecode(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return false }
        let supported = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(type as String)
    }
}
