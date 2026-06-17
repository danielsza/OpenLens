# The Aperture Library Format

This document records what we have reverse-engineered about Apple Aperture's
`*.aplibrary` package, verified against a real **version 3.6** library. It is
the reference that `OpenLensKit` is built on.

> Aperture libraries are macOS *packages* (folders that Finder shows as a single
> file). Right-click → **Show Package Contents** to browse one.

## Top-level layout

```
MyLibrary.aplibrary/
├── Info.plist                  Bundle metadata. CFBundleShortVersionString = "3.6"
├── Aperture.aplib/
│   └── DataModelVersion.plist  Schema/data-model version
├── Database/
│   ├── apdb/                   The SQLite databases (see below)
│   │   ├── Library.apdb        ★ main catalog
│   │   ├── Properties.apdb     EXIF/IPTC properties index
│   │   ├── ImageProxies.apdb   thumbnail/preview bookkeeping
│   │   ├── History.apdb        change history
│   │   ├── BigBlobs.apdb       large blobs
│   │   ├── Faces.db            face detection
│   │   └── SharingActivity.db
│   ├── Versions/               per-image plists (mirrors of the catalog)
│   │   └── <Y>/<M>/<D>/<import>/<masterUuid>/
│   │       ├── Master.apmaster    plist mirror of the RKMaster row
│   │       ├── Version-0.apversion original version (immutable)
│   │       └── Version-1.apversion current editable version (+ proxy state)
│   ├── Keywords.plist          keyword hierarchy
│   ├── KeywordSets.plist
│   └── Folders/ Albums/ Faces/ Places/ Volumes/ Vaults/ History/
├── Masters/                    the original imported files
│   └── <Y>/<M>/<D>/<import>/<file>     e.g. 2026/06/16/20260616-214247/F30A1133.JPG
├── Previews/                   full-size rendered JPEG previews
├── Thumbnails/                 grid thumbnails (multiple sizes)
├── Masks/  Attachments/  iLifeShared/
```

## The catalog: `Library.apdb`

A standard SQLite 3 database. Tables are prefixed `RK` (the internal framework
was "RedKite"). There are ~33 tables; these are the ones that matter for
browsing, rating, and export:

### `RKFolder` — projects and the folder tree
| Column | Meaning |
|---|---|
| `modelId` | integer primary key |
| `uuid` | stable identifier (system folders use names like `LibraryFolder`, `TrashFolder`) |
| `folderType` | **1 = system/structural folder, 2 = user project** |
| `name` | display name |
| `folderPath` | tree position, e.g. `1/2/10/` = root → Projects → this |
| `parentFolderUuid` | parent link |
| `versionCount` | photos in the project |
| `isInTrash`, `isHidden`, `createDate` | housekeeping |

System rows always present: `LibraryFolder`, `AllProjectsItem` ("Projects"),
`TrashFolder`, `TopLevelAlbums`, `TopLevelBooks`, etc. Real projects have
`folderType = 2`.

### `RKMaster` — the imported originals
| Column | Meaning |
|---|---|
| `uuid` | identifier (referenced by versions) |
| `fileName`, `originalFileName` | file names |
| `imagePath` | path **relative to `Masters/`**, e.g. `2026/06/16/20260616-214247/F30A1133.JPG` |
| `projectUuid` | owning project |
| `type` | `IMGT` image, `VIDT` video, etc. |
| `fileIsReference` | **1 = master stored outside the library** (referenced) |
| `isMissing` | original cannot be found |
| `isTrulyRaw`, `subtype`, `fileSize`, `imageDate` | |

### `RKVersion` — the browsable, rateable photos
One master usually has two versions: `Version-0` (original, `showInLibrary = 0`)
and `Version-1` (the live version, `showInLibrary = 1`).

| Column | Meaning |
|---|---|
| `uuid` | identifier |
| `masterUuid` | the backing master |
| `projectUuid` | owning project |
| `name`, `fileName`, `versionNumber` | |
| **`mainRating`** | **star rating 0–5** |
| **`isFlagged`** | flag |
| **`colorLabelIndex`** | colour label, −1 = none, 0–6 = colours |
| `hasAdjustments`, `hasEnabledAdjustments` | whether edits exist |
| `rotation` | orientation |
| `isOriginal`, `isEditable`, `isInTrash`, `showInLibrary` | |
| `masterWidth/Height`, `processedWidth/Height` | dimensions |
| `editListData` (BLOB), `adjSeqNum` | adjustment bookkeeping |

### Other relevant tables
- `RKImageAdjustment` — one row per adjustment (exposure, white balance,
  crop, etc.) keyed to a version. Empty when nothing has been edited.
- `RKKeyword`, `RKKeywordForVersion` — keyword vocabulary and assignments.
- `RKAlbum` — albums and smart albums (system albums: `allPhotosAlbum`,
  `flaggedAlbum`, `rejectedAlbum`, `trashAlbum`, …).
- `RKImageMask`, `RKVersionFaceContent`, `RKPlaceForVersion` — masks, faces, places.

## The per-image plists

Each master folder under `Database/Versions/.../<masterUuid>/` contains binary
property lists that **mirror** the catalog. Keeping them in sync is essential —
Aperture reads both.

- **`Master.apmaster`** — mirror of the `RKMaster` row plus `importGroup`,
  `colorSpaceName`, focus points, etc.
- **`Version-0.apversion` / `Version-1.apversion`** — mirror of the `RKVersion`
  row plus:
  - `exifProperties` — full EXIF (camera `Make`/`Model`, `LensModel`, ISO,
    `ShutterSpeed`, `ApertureValue`, `FocalLength`, GPS, capture date…).
  - `iptcProperties` — `StarRating` (string), `Byline`, `CopyrightNotice`…
  - `imageProxyState` (Version-1 only) — thumbnail/preview paths and sizes,
    e.g. `thumbnailPath`, `miniThumbnailPath` under `Thumbnails/…`.

> **Ratings appear in three places** that should agree: `RKVersion.mainRating`,
> the plist's top-level `mainRating`, and `iptcProperties.StarRating`.
> `OpenLensKit`'s writer updates all three.

## Dates

Timestamps are **seconds since 2001-01-01 UTC** (the `NSDate`/Core Data
reference date), *not* the Unix epoch. Convert with
`Date(timeIntervalSinceReferenceDate:)`.

## Practical notes & gotchas

- Treat the library as **append-mostly** and always work on a **copy** until a
  writer is proven. Aperture itself rebuilds derivative data, but we must not
  corrupt the catalog.
- Some uuids contain URL-unsafe characters (`%`, `+`) — they are literal
  identifiers, not encodings. Don't URL-decode them.
- Referenced masters (`fileIsReference = 1`) live outside the package; their
  real location is stored as a bookmark/alias (`fileAliasData` BLOB) and via
  `RKVolume`. Resolving these is on the roadmap.
- Adjustments are stored as a parameter list, not baked pixels — matching them
  exactly is the hardest part of full parity (see ROADMAP).
- **Open read-only catalogs with SQLite's `immutable=1` URI.** A plain
  read-only `SELECT` can otherwise fail with *"attempt to write a readonly
  database"* on some platforms. `immutable` also makes SQLite ignore any
  side-files.
- **Never let a stray `-journal`/`-wal`/`-shm` travel with a catalog.** If a hot
  journal is present, a read-**write** open will run rollback recovery and can
  empty the database ("no such table"). OpenLens gitignores these and the
  reader opens `immutable` (which ignores them).
- Thumbnails live under `Thumbnails/<date>/<uuid>/thumb_<name>_1024.jpg` (plus a
  `mini` size and per-face tiles). The paths are recorded in the
  `imageProxyState` of `Version-1.apversion`. A library may have **no**
  `Previews/` if full-size previews were never generated.
