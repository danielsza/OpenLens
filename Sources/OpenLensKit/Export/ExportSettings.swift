import Foundation
import ImageIO
import CoreGraphics
import CoreText

/// Aperture-style export options: format, size, resolution, quality, watermark.
public struct ExportSettings {
    public enum Format: String, CaseIterable { case originals, jpeg, png, tiff, heic }

    public var format: Format = .jpeg
    /// Long-edge cap in pixels; 0 = full resolution.
    public var maxPixelSize: Int = 0
    public var jpegQuality: Double = 0.9
    /// Optional DPI written into the file metadata.
    public var dpi: Double?
    public var watermark: Watermark?
    /// Appended to the base file name (e.g. "_web") before the extension.
    public var fileNameSuffix: String = ""
    /// Aperture-style "Custom Name with Index": non-empty renames files to
    /// "<customName> 001", "<customName> 002", … in export order.
    public var customName: String = ""
    /// Carry the source's EXIF/TIFF/IPTC/GPS metadata into the exported file.
    public var preserveMetadata: Bool = true

    public init(format: Format = .jpeg, maxPixelSize: Int = 0, jpegQuality: Double = 0.9,
                dpi: Double? = nil, watermark: Watermark? = nil, fileNameSuffix: String = "",
                customName: String = "", preserveMetadata: Bool = true) {
        self.format = format
        self.maxPixelSize = maxPixelSize
        self.jpegQuality = jpegQuality
        self.dpi = dpi
        self.watermark = watermark
        self.fileNameSuffix = fileNameSuffix
        self.customName = customName
        self.preserveMetadata = preserveMetadata
    }

    /// The output base name for the photo at `index` (1-based) in the batch.
    func baseName(for photo: Photo, index: Int) -> String {
        if !customName.isEmpty {
            return String(format: "%@ %03d%@", customName, index, fileNameSuffix)
        }
        return photo.version.name + fileNameSuffix
    }

    var fileExtension: String {
        switch format {
        case .originals: return "dat"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heic: return "heic"
        }
    }

    var uti: CFString {
        switch format {
        case .png: return "public.png" as CFString
        case .tiff: return "public.tiff" as CFString
        case .heic: return "public.heic" as CFString
        default: return "public.jpeg" as CFString
        }
    }

    /// Formats that honour the lossy-quality setting.
    var isLossy: Bool { format == .jpeg || format == .heic }
}

/// A text or image watermark drawn onto exported (rendered) images.
public struct Watermark {
    public enum Position: String, CaseIterable {
        case bottomCenter, bottomRight, bottomLeft, topCenter, topRight, topLeft, center

        public var displayName: String {
            switch self {
            case .bottomCenter: return "Bottom Center"
            case .bottomRight: return "Bottom Right"
            case .bottomLeft: return "Bottom Left"
            case .topCenter: return "Top Center"
            case .topRight: return "Top Right"
            case .topLeft: return "Top Left"
            case .center: return "Center"
            }
        }
    }
    public var text: String?
    public var imageURL: URL?
    public var opacity: Double = 0.5
    /// Watermark width as a fraction of the image width (image watermarks).
    public var scale: Double = 0.25
    public var position: Position = .bottomCenter

    public init(text: String? = nil, imageURL: URL? = nil, opacity: Double = 0.5,
                scale: Double = 0.25, position: Position = .bottomCenter) {
        self.text = text
        self.imageURL = imageURL
        self.opacity = opacity
        self.scale = scale
        self.position = position
    }
}

public extension Exporter {

    /// Exports a photo with full settings (format/size/dpi/watermark), returning
    /// the written file URL.
    @discardableResult
    func export(_ photo: Photo, to directory: URL, settings: ExportSettings,
                sequenceIndex: Int = 1) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if settings.format == .originals {
            return try export(photo, to: directory, mode: .originals)
        }

        let src = library.masterFileURL(for: photo.master)
        let base: CGImage?
        if settings.maxPixelSize <= 0 {
            base = ImageLoader.fullCGImage(at: src)
        } else {
            base = ImageLoader.cgImage(at: src, maxPixelSize: settings.maxPixelSize)
        }
        guard var cg = base else { throw ExportError.decodeFailed(photo.version.name) }
        if let params = library.olAdjustments(for: photo) {
            // Crop coordinates are in master space; scale for resized exports.
            let masterSize: CGSize? = {
                guard let w = photo.version.masterWidth, let h = photo.version.masterHeight,
                      w > 0, h > 0 else { return nil }
                return CGSize(width: w, height: h)
            }()
            cg = AdjustmentRenderer.apply(params, to: cg, masterPixelSize: masterSize)
        }
        // Apply the version's rotation (adjustment/crop coords live in
        // UN-rotated master space, so rotate after adjustments).
        if photo.version.rotation != 0 {
            cg = ImageLoader.rotate(cg, degrees: photo.version.rotation)
        }
        let rendered = Exporter.applyWatermark(cg, settings.watermark)
        let dest = uniqueURL(in: directory,
                             base: settings.baseName(for: photo, index: sequenceIndex),
                             ext: settings.fileExtension)
        let sourceMeta = settings.preserveMetadata ? Exporter.sourceMetadata(of: src) : [:]
        guard Exporter.encode(rendered, to: dest, settings: settings, sourceMetadata: sourceMeta) else {
            throw ExportError.encodeFailed(photo.version.name)
        }
        return dest
    }

    /// EXIF/TIFF/IPTC/GPS dictionaries from the source file, for carry-over.
    static func sourceMetadata(of url: URL) -> [CFString: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return [:]
        }
        var out: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary] {
            if let dict = props[key] { out[key] = dict }
        }
        return out
    }

    @discardableResult
    func exportBatch(_ photos: [Photo], to directory: URL, settings: ExportSettings)
        -> (written: [URL], failures: [(Photo, Error)]) {
        var written: [URL] = []
        var failures: [(Photo, Error)] = []
        for (index, photo) in photos.enumerated() {
            do {
                written.append(try export(photo, to: directory, settings: settings,
                                          sequenceIndex: index + 1))
            } catch { failures.append((photo, error)) }
        }
        return (written, failures)
    }

    // MARK: - Rendering

    static func encode(_ cg: CGImage, to url: URL, settings: ExportSettings,
                       sourceMetadata: [CFString: Any] = [:]) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, settings.uti, 1, nil) else {
            return false
        }
        var props: [CFString: Any] = sourceMetadata
        if settings.isLossy {
            props[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, settings.jpegQuality))
        }
        if let dpi = settings.dpi {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    static func applyWatermark(_ cg: CGImage, _ watermark: Watermark?) -> CGImage {
        guard let wm = watermark, wm.text != nil || wm.imageURL != nil else { return cg }
        let w = cg.width, h = cg.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return cg
        }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(cg, in: full)
        let margin = CGFloat(h) * 0.02

        if let imgURL = wm.imageURL,
           let isrc = CGImageSourceCreateWithURL(imgURL as CFURL, nil),
           let wmImg = CGImageSourceCreateImageAtIndex(isrc, 0, nil) {
            let tw = CGFloat(w) * CGFloat(wm.scale)
            let th = tw * CGFloat(wmImg.height) / CGFloat(wmImg.width)
            let origin = position(wm.position, size: CGSize(width: tw, height: th),
                                  in: CGSize(width: CGFloat(w), height: CGFloat(h)), margin: margin)
            ctx.setAlpha(CGFloat(wm.opacity))
            ctx.draw(wmImg, in: CGRect(origin: origin, size: CGSize(width: tw, height: th)))
            ctx.setAlpha(1)
        } else if let text = wm.text, !text.isEmpty {
            drawText(text, in: ctx, imageSize: CGSize(width: CGFloat(w), height: CGFloat(h)),
                     watermark: wm, margin: margin)
        }
        return ctx.makeImage() ?? cg
    }

    private static func position(_ p: Watermark.Position, size: CGSize,
                                 in image: CGSize, margin: CGFloat) -> CGPoint {
        // CoreGraphics origin is bottom-left.
        switch p {
        case .bottomCenter: return CGPoint(x: (image.width - size.width) / 2, y: margin)
        case .bottomLeft:   return CGPoint(x: margin, y: margin)
        case .bottomRight:  return CGPoint(x: image.width - size.width - margin, y: margin)
        case .topCenter:    return CGPoint(x: (image.width - size.width) / 2, y: image.height - size.height - margin)
        case .topLeft:      return CGPoint(x: margin, y: image.height - size.height - margin)
        case .topRight:     return CGPoint(x: image.width - size.width - margin, y: image.height - size.height - margin)
        case .center:       return CGPoint(x: (image.width - size.width) / 2, y: (image.height - size.height) / 2)
        }
    }

    private static func drawText(_ text: String, in ctx: CGContext, imageSize: CGSize,
                                 watermark wm: Watermark, margin: CGFloat) {
        let fontSize = imageSize.height * 0.04
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: CGFloat(wm.opacity))
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        guard let attr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetImageBounds(line, ctx)
        let origin = position(wm.position, size: bounds.size, in: imageSize, margin: margin)
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }
}
