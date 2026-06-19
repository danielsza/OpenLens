import Foundation
import SwiftUI
import OpenLensKit

/// Observable wrapper around an open Aperture library, driving the UI.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var library: ApertureLibrary?
    @Published var projects: [Project] = []
    @Published var projectTree: [FolderNode] = []
    @Published var userAlbums: [Album] = []
    @Published var photos: [Photo] = []
    @Published var selectedProjectID: String?
    @Published var selectedAlbumID: String?
    @Published var selectedPhotoID: String?
    @Published var errorMessage: String?

    /// Precomputed album membership (album uuid -> photos).
    private var albumPhotos: [String: [Photo]] = [:]

    /// When true, rating edits are written back to the library on disk.
    /// Default off — browsing is non-destructive until the user opts in.
    @Published var writesEnabled = false

    /// Current browser layout and thumbnail size (Aperture-style).
    @Published var viewMode: ViewMode = .split
    @Published var thumbnailSize: Double = 150

    @Published var filter = PhotoFilter()

    var visiblePhotos: [Photo] {
        let base: [Photo]
        if let aid = selectedAlbumID { base = albumPhotos[aid] ?? [] }
        else if let pid = selectedProjectID { base = photos.filter { $0.version.projectUuid == pid } }
        else { base = photos }
        return filter.apply(to: base)
    }

    func selectProject(_ id: String?) {
        selectedAlbumID = nil
        selectedProjectID = id
    }

    func selectAlbum(_ id: String?) {
        selectedProjectID = nil
        selectedAlbumID = id
    }

    var selectedPhoto: Photo? {
        photos.first { $0.id == selectedPhotoID }
    }

    func open(url: URL) {
        do {
            let lib = try ApertureLibrary(url: url)
            self.library = lib
            self.projects = try lib.projects()
            self.projectTree = (try? lib.projectNavigator()) ?? []
            self.photos = try lib.photos()
            self.userAlbums = (try? lib.userAlbums()) ?? []
            var map: [String: [Photo]] = [:]
            for album in userAlbums {
                map[album.id] = (try? lib.photos(inAlbum: album)) ?? []
            }
            self.albumPhotos = map
            self.selectedProjectID = projects.first?.id
            self.selectedAlbumID = nil
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

    func setColorLabel(_ label: Int, for photo: Photo) {
        updateLocal(photo) { $0.colorLabel = label }
        guard writesEnabled, let lib = library else { return }
        do {
            let writer = ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
            try writer.setColorLabel(label, forVersion: photo.version.id)
        } catch {
            errorMessage = "Failed to save color label: \(error)"
        }
    }

    /// Selects the next/previous photo in the visible set (arrow-key nav).
    func selectOffset(_ delta: Int) {
        let photos = visiblePhotos
        guard !photos.isEmpty else { return }
        let idx = photos.firstIndex { $0.id == selectedPhotoID } ?? 0
        let next = max(0, min(photos.count - 1, idx + delta))
        selectedPhotoID = photos[next].id
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
