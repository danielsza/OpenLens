import Foundation

/// Result of importing a folder tree.
public struct FolderImportResult: Equatable {
    public var projectsCreated = 0
    public var photosImported = 0
    public var skipped = 0          // non-image or unreadable files
}

public extension ApertureLibraryWriter {

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "gif", "bmp",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2"
    ]

    /// Imports a directory tree: every folder that directly contains images
    /// becomes a project (named after the folder), and its images are imported
    /// as managed masters. Images directly in `root` go into a project named
    /// after the root folder. Subfolders are walked recursively.
    @discardableResult
    func importFolderTree(at root: URL,
                          progress: ((String) -> Void)? = nil) throws -> FolderImportResult {
        var result = FolderImportResult()
        let fm = FileManager.default

        func imageFiles(in dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey]))
                ?? [])
                .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        func subdirectories(in dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]))
                ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { $0.pathExtension.lowercased() != "aplibrary" }   // don't recurse into libraries
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        func walk(_ dir: URL) throws {
            let images = imageFiles(in: dir)
            if !images.isEmpty {
                progress?("Importing \(images.count) photo(s) from \(dir.lastPathComponent)…")
                let projectUuid = try createProject(named: dir.lastPathComponent)
                result.projectsCreated += 1
                for file in images {
                    do {
                        _ = try importImage(at: file, intoProject: projectUuid)
                        result.photosImported += 1
                    } catch {
                        result.skipped += 1
                    }
                }
            }
            for sub in subdirectories(in: dir) {
                try walk(sub)
            }
        }

        try walk(root)
        return result
    }
}
