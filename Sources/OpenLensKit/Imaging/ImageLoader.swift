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

    /// Returns the image rotated clockwise by the given degrees (0/90/180/270).
    public static func rotate(_ cg: CGImage, degrees: Int) -> CGImage {
        let d = ((degrees % 360) + 360) % 360
        guard d != 0 else { return cg }
        let w = cg.width, h = cg.height
        let swap = (d == 90 || d == 270)
        let nw = swap ? h : w, nh = swap ? w : h
        let cs = cg.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
        ctx.rotate(by: -Double(d) * .pi / 180)            // clockwise
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    /// RGB + luminance histogram (bucketed counts) for an image.
    public struct Histogram: Equatable {
        public let red: [Int]
        public let green: [Int]
        public let blue: [Int]
        public let luminance: [Int]
        public var bucketCount: Int { luminance.count }
    }

    /// Computes a histogram by sampling a downsampled copy of the image.
    public static func histogram(at url: URL, sampleMax: Int = 160, buckets: Int = 64) -> Histogram? {
        guard let cg = cgImage(at: url, maxPixelSize: sampleMax) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = data.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: cs, bitmapInfo: bmp)
        }) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var r = [Int](repeating: 0, count: buckets)
        var g = [Int](repeating: 0, count: buckets)
        var b = [Int](repeating: 0, count: buckets)
        var l = [Int](repeating: 0, count: buckets)
        var i = 0
        while i < data.count {
            let R = Int(data[i]), G = Int(data[i + 1]), B = Int(data[i + 2])
            r[R * buckets / 256] += 1
            g[G * buckets / 256] += 1
            b[B * buckets / 256] += 1
            let lum = Int(0.299 * Double(R) + 0.587 * Double(G) + 0.114 * Double(B))
            l[min(buckets - 1, lum * buckets / 256)] += 1
            i += 4
        }
        return Histogram(red: r, green: g, blue: b, luminance: l)
    }

    /// GPS coordinate (signed lat, lon) from an image's metadata, if present.
    public static func gpsCoordinate(at url: URL) -> (latitude: Double, longitude: Double)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        return (latRef == "S" ? -lat : lat, lonRef == "W" ? -lon : lon)
    }

    /// True if ImageIO recognises the file as a decodable image.
    public static func canDecode(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return false }
        let supported = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(type as String)
    }
}
