# OpenLens

A modern, native macOS replacement for Apple Aperture — that reads and writes
**real Aperture libraries** (`*.aplibrary`) in place, preserving your projects,
versions, ratings, and metadata.

Aperture was discontinued in 2015 and nothing has truly replaced it for people
who organised their whole catalog around its projects + non-destructive
versions model. OpenLens is an attempt to bring that workflow back on modern
macOS, working directly with the libraries you already have.

> **Status: early scaffold.** Read-only browsing of the catalog works, and a
> guarded writer can set ratings/flags/labels. Everything is built on a
> documented, reverse-engineered understanding of the format
> (see [`docs/aperture-format.md`](docs/aperture-format.md)). Treat your real
> libraries as precious and **work on copies** until writing is fully proven.

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
# Inspect a library from the command line
swift run openlens-cli /path/to/MyLibrary.aplibrary
swift run openlens-cli /path/to/MyLibrary.aplibrary --list

# Run the app
swift run OpenLensApp

# Run the tests against a sample library
OPENLENS_TEST_LIBRARY=/path/to/test.aplibrary swift test
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
