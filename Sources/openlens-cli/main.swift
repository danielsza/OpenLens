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
      openlens-cli <library.aplibrary>
      openlens-cli <library.aplibrary> --list
      openlens-cli <library.aplibrary> --rate <versionUuid> <0-5>
    """)
}

let libURL = URL(fileURLWithPath: libPath)

do {
    let library = try ApertureLibrary(url: libURL)
    print("OpenLens — Aperture library v\(library.version)")
    print("Path: \(library.url.path)\n")

    let projects = try library.projects()
    let photos = try library.photos()

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
