import Foundation

public extension ApertureLibrary {

    /// Aperture's full-size rendered preview for a photo, if one exists.
    /// Layout (verified against a real 3.6 library):
    /// `Previews/<master's date path>/<version uuid>/<version name>.jpg`
    func previewURL(for photo: Photo) -> URL? {
        let datePath = (photo.master.imagePath as NSString).deletingLastPathComponent
        let dir = previewsURL
            .appendingPathComponent(datePath)
            .appendingPathComponent(photo.version.id)
        let fm = FileManager.default
        let exact = dir.appendingPathComponent("\(photo.version.name).jpg")
        if fm.fileExists(atPath: exact.path) { return exact }
        // Fallback: any image file in the version's preview folder.
        if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            return items.first { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        }
        return nil
    }

    /// Best source for the large viewer: the rendered preview (which reflects
    /// Aperture's edits!) when present, else the master, else the thumbnail.
    func viewerImageURL(for photo: Photo) -> URL {
        if let preview = previewURL(for: photo) { return preview }
        let master = masterFileURL(for: photo.master)
        if FileManager.default.fileExists(atPath: master.path) { return master }
        return thumbnailURL(for: photo) ?? master
    }
}
