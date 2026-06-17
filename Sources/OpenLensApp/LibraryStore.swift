import Foundation
import SwiftUI
import OpenLensKit

/// Observable wrapper around an open Aperture library, driving the UI.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var library: ApertureLibrary?
    @Published var projects: [Project] = []
    @Published var photos: [Photo] = []
    @Published var selectedProjectID: String?
    @Published var selectedPhotoID: String?
    @Published var errorMessage: String?

    /// When true, rating edits are written back to the library on disk.
    /// Default off — browsing is non-destructive until the user opts in.
    @Published var writesEnabled = false

    var visiblePhotos: [Photo] {
        guard let pid = selectedProjectID else { return photos }
        return photos.filter { $0.version.projectUuid == pid }
    }

    var selectedPhoto: Photo? {
        photos.first { $0.id == selectedPhotoID }
    }

    func open(url: URL) {
        do {
            let lib = try ApertureLibrary(url: url)
            self.library = lib
            self.projects = try lib.projects()
            self.photos = try lib.photos()
            self.selectedProjectID = projects.first?.id
            self.errorMessage = nil
        } catch {
            self.errorMessage = "\(error)"
        }
    }

    func setRating(_ rating: Int, for photo: Photo) {
        updateLocal(photo) { $0.rating = rating }
        guard writesEnabled, let lib = library else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            try writer.setRating(rating, forVersion: photo.version.id)
        } catch {
            errorMessage = "Failed to save rating: \(error)"
        }
    }

    func toggleFlag(for photo: Photo) {
        let newValue = !photo.version.isFlagged
        updateLocal(photo) { $0.isFlagged = newValue }
        guard writesEnabled, let lib = library else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            try writer.setFlagged(newValue, forVersion: photo.version.id)
        } catch {
            errorMessage = "Failed to save flag: \(error)"
        }
    }

    /// Updates the in-memory copy so the UI reflects edits immediately.
    private func updateLocal(_ photo: Photo, _ mutate: (inout PhotoVersion) -> Void) {
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        var version = photos[idx].version
        mutate(&version)
        photos[idx] = Photo(version: version, master: photos[idx].master)
    }
}
