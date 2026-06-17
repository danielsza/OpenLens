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

    print("\nPhotos (\(photos.count)):")
    if args.contains("--list") {
        for photo in photos {
            let v = photo.version
            let stars = v.rating > 0 ? String(repeating: "★", count: v.rating) : "—"
            let flag = v.isFlagged ? " ⚑" : ""
            let adj = v.hasAdjustments ? " [edited]" : ""
            print("  \(v.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(stars)\(flag)\(adj)  \(photo.master.fileName)")
        }
    } else {
        print("  (pass --list to see them all)")
    }
} catch {
    fail("Error: \(error)")
}
