import Foundation
import OpenLensKit

// A small command-line tool to exercise OpenLensKit against a real library.
//
//   swift run openlens-cli <path-to.aplibrary>            # summary
//   swift run openlens-cli <path> --list                  # list every photo
//   swift run openlens-cli <path> --rate <versionUuid> <0-5>   # (writes!)
//
// The --rate command mutates the library and is intentionally gated; only use
// it on a COPY until the writer has been validated on your data.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let libPath = args.first else {
    fail("""
    Usage:
      openlens-cli <library.aplibrary> [--list] [--meta]
      openlens-cli <library.aplibrary> --search <query>
      openlens-cli <library.aplibrary> --export <dir> [--rendered --size N]
      openlens-cli <library.aplibrary> --rate <versionUuid> <-1..5>
      openlens-cli <new.aplibrary> --create [projectName]
      openlens-cli <library.aplibrary> --new-project <name>
      openlens-cli <library.aplibrary> --import <projectUuid> <file...>
      openlens-cli <library.aplibrary> --duplicate <versionUuid>
    """)
}

let libURL = URL(fileURLWithPath: libPath)

do {
    // Create a brand-new library: openlens-cli <new.aplibrary> --create [projectName]
    if args.contains("--create"), let i = args.firstIndex(of: "--create") {
        let name = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1] : nil
        let lib = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: name)
        print("Created library at \(lib.url.path)")
        if let p = try lib.projects().first { print("Project: \(p.name)  uuid=\(p.id)") }
        exit(0)
    }

    let library = try ApertureLibrary(url: libURL)
    print("OpenLens — Aperture library v\(library.version)")
    print("Path: \(library.url.path)\n")

    let projects = try library.projects()
    let photos = try library.photos()

    if args.contains("--new-project"), let i = args.firstIndex(of: "--new-project") {
        guard i + 1 < args.count else { fail("--new-project requires a name") }
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let uuid = try writer.createProject(named: args[i + 1])
        print("Created project \"\(args[i + 1])\"  uuid=\(uuid)")
        exit(0)
    }

    if args.contains("--import"), let i = args.firstIndex(of: "--import") {
        guard i + 1 < args.count else { fail("--import requires <projectUuid> <file...>") }
        let projectUuid = args[i + 1]
        let files = Array(args[(i + 2)...]).filter { !$0.hasPrefix("--") }
        guard !files.isEmpty else { fail("--import requires at least one file") }
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        var ok = 0
        for f in files {
            do { _ = try writer.importImage(at: URL(fileURLWithPath: f), intoProject: projectUuid); ok += 1 }
            catch { print("  ⚠️  \(f): \(error)") }
        }
        print("Imported \(ok)/\(files.count) file(s) into \(projectUuid)")
        exit(ok == files.count ? 0 : 1)
    }

    if args.contains("--duplicate"), let i = args.firstIndex(of: "--duplicate") {
        guard i + 1 < args.count else { fail("--duplicate requires <versionUuid>") }
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        let newUuid = try writer.duplicateVersion(args[i + 1])
        print("Duplicated \(args[i + 1]) -> \(newUuid)")
        exit(0)
    }

    if args.contains("--search"), let i = args.firstIndex(of: "--search") {
        guard i + 1 < args.count else { fail("--search requires a query") }
        let hits = try library.search(args[i + 1])
        print("Search \"\(args[i + 1])\" — \(hits.count) result(s):")
        for p in hits {
            let stars = p.version.rating > 0 ? String(repeating: "★", count: p.version.rating) : "—"
            print("  \(p.version.name)  \(stars)  \(p.master.fileName)")
        }
        exit(0)
    }

    if args.contains("--export"), let i = args.firstIndex(of: "--export") {
        guard i + 1 < args.count else { fail("--export requires a destination directory") }
        let dest = URL(fileURLWithPath: args[i + 1])
        let exporter = Exporter(library: library)
        let mode: Exporter.Mode
        if args.contains("--rendered") {
            let size = args.firstIndex(of: "--size").flatMap { args.indices.contains($0+1) ? Int(args[$0+1]) : nil } ?? 2048
            mode = .rendered(maxPixelSize: size, quality: 0.9)
        } else {
            mode = .originals
        }
        let result = exporter.exportBatch(photos, to: dest, mode: mode)
        print("Exported \(result.written.count) file(s) to \(dest.path)")
        for (photo, error) in result.failures {
            print("  ⚠️  \(photo.version.name): \(error)")
        }
        exit(result.failures.isEmpty ? 0 : 1)
    }

    if args.contains("--rate"), let i = args.firstIndex(of: "--rate") {
        guard i + 2 < args.count, let stars = Int(args[i + 2]) else {
            fail("--rate requires <versionUuid> <0-5>")
        }
        let uuid = args[i + 1]
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        try writer.setRating(stars, forVersion: uuid)
        print("Set rating \(stars)★ on version \(uuid).")
        exit(0)
    }

    print("Projects (\(projects.count)):")
    for p in projects {
        let count = photos.filter { $0.version.projectUuid == p.id }.count
        print("  • \(p.name)  [\(count) photos]  uuid=\(p.id)")
    }

    let userAlbums = (try? library.userAlbums()) ?? []
    if !userAlbums.isEmpty {
        print("\nAlbums (\(userAlbums.count)):")
        for a in userAlbums {
            let count = (try? library.photos(inAlbum: a).count) ?? 0
            print("  • \(a.displayName)  [\(count) photos]")
        }
    }
    let vocab = (try? library.keywordVocabulary()) ?? []
    print("\nKeyword vocabulary: \(vocab.count) terms")
    let stacks = (try? library.stacks()) ?? []
    if !stacks.isEmpty { print("Stacks: \(stacks.count)") }

    if let s = try? library.statistics() {
        let hist = (0...5).map { "\($0)★:\(s.ratingHistogram[$0] ?? 0)" }.joined(separator: " ")
        print("\nStats: \(s.photoCount) photos, \(s.flaggedCount) flagged, \(s.editedCount) edited")
        print("Ratings: \(hist)")
    }

    print("\nPhotos (\(photos.count)):")
    if args.contains("--list") {
        let showMeta = args.contains("--meta")
        for photo in photos {
            let v = photo.version
            let stars = v.rating > 0 ? String(repeating: "★", count: v.rating) : "—"
            let flag = v.isFlagged ? " ⚑" : ""
            let adj = v.hasAdjustments ? " [edited]" : ""
            print("  \(v.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(stars)\(flag)\(adj)  \(photo.master.fileName)")
            if showMeta, let m = library.metadata(for: photo) {
                let cam = [m.cameraMake, m.cameraModel].compactMap { $0 }.joined(separator: " ")
                let thumb = library.thumbnailURL(for: photo) != nil ? "thumb✓" : "thumb✗"
                print("      \(cam.isEmpty ? "—" : cam)  \(m.exposureSummary)  \(thumb)")
            }
        }
    } else {
        print("  (pass --list to see them all, add --meta for EXIF)")
    }
} catch {
    fail("Error: \(error)")
}
