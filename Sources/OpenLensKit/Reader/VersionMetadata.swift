import Foundation

/// Rich metadata for a version, parsed from its `Version-N.apversion` property
/// list. The plist mirrors the catalog and additionally carries the full EXIF
/// and IPTC dictionaries plus `imageProxyState` (thumbnail/preview paths).
public struct VersionMetadata: Hashable {
    // Camera / capture
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int?
    /// Shutter speed in seconds (e.g. 0.002 == 1/500s).
    public var shutterSpeed: Double?
    /// Aperture f-number, derived from the EXIF APEX `ApertureValue`.
    public var fNumber: Double?
    /// Focal length in millimetres.
    public var focalLength: Double?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var colorModel: String?
    public var profileName: String?

    // Location
    public var latitude: Double?
    public var longitude: Double?

    // Rights / IPTC
    public var artist: String?
    public var copyright: String?
    public var caption: String?
    public var title: String?
    public var byline: String?

    // Proxy (thumbnail/preview) bookkeeping, relative to the library's
    // `Thumbnails/` directory.
    public var thumbnailPath: String?
    public var miniThumbnailPath: String?
    public var thumbnailWidth: Int?
    public var thumbnailHeight: Int?

    public init() {}

    /// A compact "1/500s · f/8 · ISO 500 · 60mm" style summary, omitting any
    /// values that are missing.
    public var exposureSummary: String {
        var parts: [String] = []
        if let s = shutterSpeed { parts.append(Self.formatShutter(s)) }
        if let f = fNumber { parts.append(String(format: "f/%g", f)) }
        if let iso { parts.append("ISO \(iso)") }
        if let fl = focalLength { parts.append(String(format: "%gmm", fl)) }
        return parts.joined(separator: " · ")
    }

    static func formatShutter(_ seconds: Double) -> String {
        if seconds <= 0 { return "" }
        if seconds >= 1 { return String(format: "%gs", seconds) }
        return "1/\(Int((1.0 / seconds).rounded()))s"
    }
}

public extension ApertureLibrary {

    /// Locates the `.apversion` plist backing a version. The plist lives under
    /// `Database/Versions/<date>/<masterUuid>/Version-N.apversion`, where the
    /// date path comes from the master's `imagePath`.
    func versionPlistURL(for photo: Photo) -> URL? {
        let datePath = (photo.master.imagePath as NSString).deletingLastPathComponent
        let dir = versionsURL
            .appendingPathComponent(datePath)
            .appendingPathComponent(photo.master.id)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        // Prefer the plist whose uuid matches the browsed version; fall back to
        // the highest-numbered Version-N file.
        var fallback: URL?
        for url in items where url.pathExtension == "apversion" {
            fallback = url
            if let dict = Self.readPlist(url),
               (dict["uuid"] as? String) == photo.version.id {
                return url
            }
        }
        return fallback
    }

    /// Parses metadata for a photo. Returns `nil` if the plist is unreadable.
    func metadata(for photo: Photo) -> VersionMetadata? {
        guard let url = versionPlistURL(for: photo),
              let dict = Self.readPlist(url) else { return nil }
        return Self.parseMetadata(dict)
    }

    /// Absolute URL of the cached 1024px thumbnail for a photo, if present.
    func thumbnailURL(for photo: Photo) -> URL? {
        guard let meta = metadata(for: photo) else { return nil }
        if let p = meta.thumbnailPath {
            let u = thumbnailsURL.appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let p = meta.miniThumbnailPath {
            let u = thumbnailsURL.appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Best available display image: the cached thumbnail if present, else the
    /// original master file. Callers can decode this with ImageIO.
    func displayImageURL(for photo: Photo) -> URL {
        thumbnailURL(for: photo) ?? masterFileURL(for: photo.master)
    }

    // MARK: - Parsing helpers

    static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    static func parseMetadata(_ dict: [String: Any]) -> VersionMetadata {
        var m = VersionMetadata()
        let exif = dict["exifProperties"] as? [String: Any] ?? [:]
        let iptc = dict["iptcProperties"] as? [String: Any] ?? [:]
        let proxy = dict["imageProxyState"] as? [String: Any] ?? [:]

        m.cameraMake = exif["Make"] as? String
        m.cameraModel = exif["Model"] as? String
        m.lensModel = exif["LensModel"] as? String
        m.iso = (exif["ISOSpeedRating"] as? NSNumber)?.intValue
        m.shutterSpeed = (exif["ShutterSpeed"] as? NSNumber)?.doubleValue
        if let f = (exif["FNumber"] as? NSNumber)?.doubleValue {
            // Direct f-number (how OpenLens writes imported photos).
            m.fNumber = f
        } else if let apex = (exif["ApertureValue"] as? NSNumber)?.doubleValue {
            // EXIF ApertureValue is APEX: f-number = 2^(APEX/2).
            m.fNumber = (pow(2.0, apex / 2.0) * 10).rounded() / 10
        }
        m.focalLength = (exif["FocalLength"] as? NSNumber)?.doubleValue
        m.pixelWidth = (exif["PixelWidth"] as? NSNumber)?.intValue
        m.pixelHeight = (exif["PixelHeight"] as? NSNumber)?.intValue
        m.colorModel = exif["ColorModel"] as? String
        m.profileName = exif["ProfileName"] as? String
        m.latitude = (exif["Latitude"] as? NSNumber)?.doubleValue
        m.longitude = (exif["Longitude"] as? NSNumber)?.doubleValue
        m.artist = (exif["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        m.copyright = (iptc["CopyrightNotice"] as? String) ?? (exif["Copyright"] as? String)
        m.caption = (iptc["Caption"] as? String) ?? (iptc["Caption/Abstract"] as? String)
        m.title = (iptc["Title"] as? String) ?? (iptc["ObjectName"] as? String)
        m.byline = (iptc["Byline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        m.thumbnailPath = proxy["thumbnailPath"] as? String
        m.miniThumbnailPath = proxy["miniThumbnailPath"] as? String
        m.thumbnailWidth = (proxy["thumbnailWidth"] as? NSNumber)?.intValue
        m.thumbnailHeight = (proxy["thumbnailHeight"] as? NSNumber)?.intValue
        return m
    }
}
