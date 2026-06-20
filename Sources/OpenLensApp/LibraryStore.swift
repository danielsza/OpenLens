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
    @Published var selectedSource: LibrarySource?
    @Published var selectedPhotoID: String?          // primary/anchor selection
    @Published var selectedPhotoIDs: Set<String> = [] // full multi-selection
    @Published var errorMessage: String?

    /// Precomputed album membership (album uuid -> photos).
    private var albumPhotos: [String: [Photo]] = [:]
    /// Photos currently in the trash.
    private(set) var trashed: [Photo] = []

    /// Aperture-style smart sources in the Library tab.
    enum LibrarySource: String, CaseIterable, Identifiable {
        case allPhotos = "Photos"
        case flagged = "Flagged"
        case rejected = "Rejected"
        case trash = "Trash"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .allPhotos: return "photo.on.rectangle"
            case .flagged: return "flag"
            case .rejected: return "xmark.circle"
            case .trash: return "trash"
            }
        }
    }

    /// When true, rating edits are written back to the library on disk.
    /// Default off — browsing is non-destructive until the user opts in.
    @Published var writesEnabled = false

    /// Current browser layout and thumbnail size (Aperture-style).
    @Published var viewMode: ViewMode = .split
    @Published var thumbnailSize: Double = 150

    @Published var filter = PhotoFilter()
    @Published var sort: PhotoSort = .date
    @Published var sortAscending = true

    var visiblePhotos: [Photo] {
        let base: [Photo]
        if let source = selectedSource {
            switch source {
            case .allPhotos: base = photos
            case .flagged: base = photos.filter { $0.version.isFlagged }
            case .rejected: base = photos.filter { $0.version.rating < 0 }
            case .trash: base = trashed
            }
        } else if let aid = selectedAlbumID {
            base = albumPhotos[aid] ?? []
        } else if let pid = selectedProjectID {
            base = photos.filter { $0.version.projectUuid == pid }
        } else {
            base = photos
        }
        return filter.apply(to: base).sorted(by: sort, ascending: sortAscending)
    }

    func selectProject(_ id: String?) {
        selectedSource = nil
        selectedAlbumID = nil
        selectedProjectID = id
        clearSelection()
    }

    func selectAlbum(_ id: String?) {
        selectedSource = nil
        selectedProjectID = nil
        selectedAlbumID = id
        clearSelection()
    }

    func selectSource(_ source: LibrarySource?) {
        selectedProjectID = nil
        selectedAlbumID = nil
        selectedSource = source
        clearSelection()
    }

    private func clearSelection() {
        selectedPhotoID = nil
        selectedPhotoIDs = []
    }

    // MARK: - Multi-selection

    /// True if a photo should appear selected (in the multi-set, or the lone
    /// primary when the set is empty).
    func isSelected(_ id: String) -> Bool {
        selectedPhotoIDs.contains(id) || (selectedPhotoIDs.isEmpty && id == selectedPhotoID)
    }

    /// Handles a thumbnail click with optional Command (toggle) / Shift (range).
    func handleTap(_ photo: Photo, command: Bool, shift: Bool) {
        if command {
            if selectedPhotoIDs.contains(photo.id) { selectedPhotoIDs.remove(photo.id) }
            else { selectedPhotoIDs.insert(photo.id) }
            selectedPhotoID = photo.id
        } else if shift, let anchor = selectedPhotoID,
                  let ai = visiblePhotos.firstIndex(where: { $0.id == anchor }),
                  let ti = visiblePhotos.firstIndex(where: { $0.id == photo.id }) {
            let range = ai <= ti ? ai...ti : ti...ai
            selectedPhotoIDs = Set(visiblePhotos[range].map { $0.id })
            selectedPhotoID = photo.id
        } else {
            selectedPhotoID = photo.id
            selectedPhotoIDs = [photo.id]
        }
    }

    /// The photos a batch action should affect (the multi-set, else the primary).
    private func selectionPhotos() -> [Photo] {
        let ids = selectedPhotoIDs.isEmpty
            ? Set([selectedPhotoID].compactMap { $0 })
            : selectedPhotoIDs
        return photos.filter { ids.contains($0.id) }
    }

    func setRatingForSelection(_ rating: Int) {
        selectionPhotos().forEach { setRating(rating, for: $0) }
    }
    func setFlagForSelection(_ flagged: Bool) {
        selectionPhotos().forEach { if $0.version.isFlagged != flagged { toggleFlag(for: $0) } }
    }
    func setColorLabelForSelection(_ label: Int) {
        selectionPhotos().forEach { setColorLabel(label, for: $0) }
    }

    var selectedPhoto: Photo? {
        photos.first { $0.id == selectedPhotoID }
    }

    private let lastLibraryKey = "OpenLens.lastLibraryPath"

    /// The most recently opened library path, if any.
    var lastLibraryURL: URL? {
        UserDefaults.standard.string(forKey: lastLibraryKey).map { URL(fileURLWithPath: $0) }
    }

    /// Opens the last-used library if it still exists. Returns false if there is
    /// none or it's missing (caller should then show the open dialog).
    @discardableResult
    func openLastIfAvailable() -> Bool {
        guard let url = lastLibraryURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        open(url: url)
        return library != nil
    }

    /// Closes the current library without quitting the app (returns to the
    /// "no library open" state so the user can open or switch).
    /// Reloads the current library from disk (after a structural change).
    func reload() {
        if let url = library?.url { open(url: url) }
    }

    private func makeWriter() -> ApertureLibraryWriter? {
        guard let lib = library else { return nil }
        return ApertureLibraryWriter(libraryURL: lib.url, allowWrites: true)
    }

    func moveToTrash(_ photo: Photo) {
        guard let w = makeWriter() else { return }
        do { try w.moveToTrash(versionUuid: photo.version.id); reload() }
        catch { errorMessage = "Couldn't move to trash: \(error)" }
    }

    /// Moves the whole current selection to the trash.
    func moveSelectionToTrash() {
        let ids = selectedPhotoIDs.isEmpty ? [selectedPhotoID].compactMap { $0 } : Array(selectedPhotoIDs)
        guard !ids.isEmpty, let w = makeWriter() else { return }
        do { for id in ids { try w.moveToTrash(versionUuid: id) }; reload() }
        catch { errorMessage = "Couldn't move to trash: \(error)" }
    }

    func restoreFromTrash(_ photo: Photo) {
        guard let w = makeWriter() else { return }
        do { try w.restoreFromTrash(versionUuid: photo.version.id); reload() }
        catch { errorMessage = "Couldn't restore: \(error)" }
    }

    @discardableResult
    func addKeyword(_ name: String, to photo: Photo) -> Bool {
        guard let w = makeWriter() else { return false }
        do { try w.addKeyword(name, toVersion: photo.version.id); return true }
        catch { errorMessage = "Couldn't add keyword: \(error)"; return false }
    }

    func removeKeyword(_ name: String, from photo: Photo) {
        guard let w = makeWriter() else { return }
        do { try w.removeKeyword(name, fromVersion: photo.version.id) }
        catch { errorMessage = "Couldn't remove keyword: \(error)" }
    }

    func emptyTrash() {
        guard let w = makeWriter() else { return }
        do { _ = try w.emptyTrash(); reload() }
        catch { errorMessage = "Couldn't empty trash: \(error)" }
    }

    func closeLibrary() {
        library = nil
        projects = []
        projectTree = []
        userAlbums = []
        photos = []
        albumPhotos = [:]
        trashed = []
        selectedProjectID = nil
        selectedAlbumID = nil
        selectedSource = nil
        selectedPhotoID = nil
        errorMessage = nil
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
            self.trashed = (try? lib.trashedPhotos()) ?? []
            self.selectedProjectID = projects.first?.id
            self.selectedAlbumID = nil
            self.selectedSource = nil
            self.errorMessage = nil
            UserDefaults.standard.set(url.path, forKey: lastLibraryKey)
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
        selectedPhotoIDs = [photos[next].id]
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
