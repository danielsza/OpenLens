# OpenLens

A modern, native macOS replacement for Apple Aperture — that reads and writes
**real Aperture libraries** (`*.aplibrary`) in place, preserving your projects,
versions, ratings, and metadata.

Aperture was discontinued in 2015 and nothing has truly replaced it for people
who organised their whole catalog around its projects + non-destructive
versions model. OpenLens is an attempt to bring that workflow back on modern
macOS, working directly with the libraries you already have.

> **Status: working app.** A full create → import → browse → organise → export
> loop runs today, in an Aperture-style dark UI (Grid/Split/Viewer, tabbed
> Library/Info/Adjustments inspector, filmstrip, control bar), with last-library
> memory. Reading: projects, folders (nested), albums + smart albums, keywords,
> stacks, EXIF/IPTC, GPS, adjustments (listed), RAW-aware thumbnails. Editing
> (tested, opt-in, DB + `.apversion` plist kept in sync): ratings (incl.
> Reject), flags, colour labels, keywords, trash (move/restore/empty),
> duplicate version. Authoring: create a new library, projects, albums, and
> import photos (with generated thumbnail + EXIF). Plus filter, search,
> statistics, and export (originals + rendered JPEG). All on a documented,
> reverse-engineered format ([`docs/aperture-format.md`](docs/aperture-format.md))
> and a CI suite (60 tests) against a synthetic fixture, which also publishes a
> runnable `OpenLens.app`.
>
> **Not yet:** rendering adjustments (the edit *parameters* still need decoding
> from a real edited library) and full byte-for-byte Aperture authoring. Treat
> real libraries as precious and **work on copies** until writing is
> battle-tested.

## Goals (feature parity with Aperture)

- Open existing `.aplibrary` packages without converting or migrating them.
- Browse the **project / folder** hierarchy exactly as Aperture organised it.
- View photos with **ratings, flags, colour labels, and keywords**.
- **Edit** ratings/flags/labels/keywords and write them safely back to the library.
- Basic non-destructive **adjustments** (exposure, white balance, crop, etc.).
- **Open in external editor** round-tripping.
- **Export** originals and rendered versions with metadata.
- Honour **referenced masters** (files stored outside the library).

See [`ROADMAP.md`](ROADMAP.md) for the phased plan.

## Architecture

```
OpenLens/
├── Package.swift
├── Sources/
│   ├── OpenLensKit/        ← core library (no UI, fully testable)
│   │   ├── Database/       SQLiteDatabase — tiny dependency-free SQLite wrapper
│   │   ├── Models/         Project, PhotoMaster, PhotoVersion, Photo
│   │   ├── Reader/         ApertureLibrary — opens & reads a library
│   │   └── Writer/         ApertureLibraryWriter — guarded rating/flag/label writes
│   ├── openlens-cli/       ← command-line inspector (proves the reader works)
│   └── OpenLensApp/        ← SwiftUI app (sidebar · grid · inspector)
├── Tests/OpenLensKitTests/ ← runs against a real library via env var
└── docs/                   ← format notes + build/setup guide
```

The core has **no third-party dependencies**: SQLite via the system `SQLite3`
module, property lists via Foundation.

## Quick start

Requires macOS 13+ and a Swift toolchain (Xcode 15+).

```bash
# Run the app
swift run OpenLensApp

# Inspect / author a library from the command line
swift run openlens-cli /path/to/MyLibrary.aplibrary --list --meta
swift run openlens-cli /path/to/MyLibrary.aplibrary --search "canon beach"
swift run openlens-cli /path/to/New.aplibrary --create "My Project"
swift run openlens-cli /path/to/MyLibrary.aplibrary --import <projectUuid> a.jpg b.jpg
swift run openlens-cli /path/to/MyLibrary.aplibrary --export /tmp/out --rendered --size 2048

# Run the tests against the committed synthetic fixture
OPENLENS_TEST_LIBRARY=Tests/Fixtures/Mini.aplibrary swift test

# Prefer not to build? Download OpenLens.app from the repo's Actions ▸ latest run ▸ Artifacts.
```

You can also just open the folder in Xcode (File ▸ Open…) — it reads
`Package.swift` directly.

See [`docs/building.md`](docs/building.md) for promoting the SwiftUI target to a
full Xcode `.app` (bundle, icon, entitlements).

## Safety

OpenLens never modifies a library unless you explicitly enable writes
(`allowWrites: true` in the writer, or the "Save edits" toggle in the app).
Even then: **back up, or work on a copy.** Reverse-engineered formats deserve
caution.

## License

MIT — see [`LICENSE`](LICENSE).

---

*OpenLens is an independent project and is not affiliated with or endorsed by
Apple. "Aperture" is a trademark of Apple Inc., used here only to describe
compatibility.*
