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
    func fullImage(for photo: Photo, in library: ApertureLibrary,
                   adjustments: OLAdjustments? = nil,
                   layersOverride: [OLLocalAdjustment]? = nil) async -> NSImage? {
        let rotation = photo.version.rotation
        // Live override wins; else any saved OpenLens adjustments.
        let params = adjustments ?? library.olAdjustments(for: photo)
        let layers = layersOverride ?? library.olLocalAdjustments(for: photo)
        let layersKey = (try? OLLocalAdjustment.encodeList(layers))?.hashValue ?? 0
        let k = key("\(photo.id)#\(rotation)#\(params?.cacheKey ?? "-")#L\(layersKey)", 0)
        if let hit = cache.object(forKey: k) { return hit }
        // With OpenLens adjustments active, render from the MASTER so our
        // params fully define the look (applying them over Aperture's baked
        // preview would double-apply edits). Otherwise prefer the preview.
        let url: URL
        if params != nil || !layers.isEmpty {
            let master = library.masterFileURL(for: photo.master)
            url = FileManager.default.fileExists(atPath: master.path)
                ? master
                : library.viewerImageURL(for: photo)
        } else {
            url = library.viewerImageURL(for: photo)
        }
        // Previews/thumbnails are already rotated by Aperture; only rotate masters.
        let applyRotation = (url == library.masterFileURL(for: photo.master)) ? rotation : 0
        let masterSize: CGSize? = {
            guard let w = photo.version.masterWidth, let h = photo.version.masterHeight,
                  w > 0, h > 0 else { return nil }
            return CGSize(width: w, height: h)
        }()
        // When adjusting a RAW master, develop it through CIRAWFilter with
        // Aperture's original Raw Fine Tuning (boost/sharpen) for fidelity.
        let rawTuning: RawFineTuning? = {
            guard params != nil, RawRenderer.isRawFile(url) else { return nil }
            let rawOp = library.decodedApertureAdjustments(for: photo)
                .first { $0.identifier == "RKRawDecodeOperation" }
            return rawOp.flatMap(RawFineTuning.init(from:)) ?? RawFineTuning()
        }()
        let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            var base: CGImage?
            if let rawTuning {
                base = RawRenderer.render(at: url, tuning: rawTuning, maxPixelSize: 2400)
            }
            base = base ?? ImageLoader.cgImage(at: url, maxPixelSize: 2400)
            guard var image = base else { return nil }
            if params != nil || !layers.isEmpty {
                image = AdjustmentRenderer.applyStack(global: params ?? OLAdjustments(),
                                                      layers: layers, to: image,
                                                      masterPixelSize: masterSize)
            }
            return ImageLoader.rotate(image, degrees: applyRotation)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: k)
        return image
    }
}
