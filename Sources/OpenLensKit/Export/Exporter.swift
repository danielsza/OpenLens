import Foundation
import ImageIO
import CoreGraphics

/// Exports photos out of a library: either the untouched original master, or a
/// rendered JPEG (optionally resized). This is the read-only counterpart to the
/// eventual adjustment pipeline — for now "rendered" means the master decoded
/// and re-encoded, since adjustments aren't applied yet.
public struct Exporter {

    public enum ExportError: Error, CustomStringConvertible {
        case masterUnavailable(String)
        case decodeFailed(String)
        case encodeFailed(String)

        public var description: String {
            switch self {
            case .masterUnavailable(let n): return "Master file unavailable for \(n)"
            case .decodeFailed(let n): return "Could not decode \(n)"
            case .encodeFailed(let n): return "Could not encode \(n)"
            }
        }
    }

    public enum Mode {
        case originals                 // copy the master byte-for-byte
        case rendered(maxPixelSize: Int, quality: Double)  // re-encode as JPEG
    }

    private let library: ApertureLibrary

    public init(library: ApertureLibrary) {
        self.library = library
    }

    /// Exports a single photo to `directory`, returning the written file URL.
    @discardableResult
    public func export(_ photo: Photo, to directory: URL, mode: Mode) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        switch mode {
        case .originals:
            let src = library.masterFileURL(for: photo.master)
            guard fm.fileExists(atPath: src.path) else {
                throw ExportError.masterUnavailable(photo.version.name)
            }
            let dst = uniqueURL(in: directory,
                                base: photo.version.name,
                                ext: src.pathExtension.isEmpty ? "dat" : src.pathExtension)
            try fm.copyItem(at: src, to: dst)
            return dst

        case .rendered(let maxPixelSize, let quality):
            let src = library.masterFileURL(for: photo.master)
            let cg: CGImage?
            if maxPixelSize <= 0 {
                cg = ImageLoader.fullCGImage(at: src)
            } else {
                cg = ImageLoader.cgImage(at: src, maxPixelSize: maxPixelSize)
            }
            guard let image = cg else { throw ExportError.decodeFailed(photo.version.name) }
            let dst = uniqueURL(in: directory, base: photo.version.name, ext: "jpg")
            guard let dest = CGImageDestinationCreateWithURL(
                dst as CFURL, "public.jpeg" as CFString, 1, nil) else {
                throw ExportError.encodeFailed(photo.version.name)
            }
            let props: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality))
            ]
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                throw ExportError.encodeFailed(photo.version.name)
            }
            return dst
        }
    }

    /// Exports many photos, returning the URLs written. Errors for individual
    /// photos are collected and rethrown at the end so one bad file doesn't
    /// abort the whole batch.
    @discardableResult
    public func exportBatch(_ photos: [Photo], to directory: URL, mode: Mode)
        -> (written: [URL], failures: [(Photo, Error)]) {
        var written: [URL] = []
        var failures: [(Photo, Error)] = []
        for photo in photos {
            do { written.append(try export(photo, to: directory, mode: mode)) }
            catch { failures.append((photo, error)) }
        }
        return (written, failures)
    }

    private func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
