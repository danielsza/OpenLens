# Changelog

All notable changes to OpenLens. Dates are ISO-8601.

## [Unreleased]

### 2026-07-23 — Real-library validation, Faces, Places, import tools
- **Validated against a real 676MB Aperture library** (263 masters, 2006–2019):
  reader, plists, thumbnails, keywords all resolve; zero inconsistencies.
- **Faces**: read detected faces + names from `Faces.db` (587/587 real
  detections validated); viewer overlay toggled with **F**.
- **Places**: MapKit map of geotagged photos with clickable pins (⌥⌘P).
- **Previews**: full-size rendered previews resolved (27/27 real) and preferred
  by the viewer — edited photos display with Aperture's edits baked in.
- **Duplicates**: content-hash duplicate finder (CLI `--duplicates` + review UI
  with per-copy trash).
- **Folder-tree import**: folders → projects ("+" menu / `--import-tree`).
- **Consistency**: `--verify` checker + `--repair` (regenerates thumbnails/
  plists, prunes dangling rows, marks missing masters).
- **Export**: metadata preservation (EXIF/IPTC/GPS carry-over), persisted
  settings, custom size, filename suffix, logo watermark, Bottom Center default.
- **App**: Loupe (`), app icon, release workflow (tag `v*` → GitHub Release),
  viewer-source indicator, neighbour prefetch, wrench badge on edited photos.

### 2026-06-19/20 — Aperture-parity push
- Aperture-style UI (light-grey chrome + dark photo area, tabbed
  Library/Info/Adjustments inspector, Grid/Split/Viewer, filmstrip, control
  bar, keyboard shortcuts incl. Reject).
- Library session behavior: auto-open last library, New/Open/Switch/Close.
- Multi-selection with batch rate/flag/label/trash; sort; smart albums
  (saved filters); "N of M" status.
- Editing: keywords (chips UI), IPTC (title/caption/byline/copyright), rotate,
  duplicate version, trash incl. guarded permanent delete.
- Authoring: create library/projects/albums, import photos (thumbnail + EXIF +
  GPS generated), stacks (create/break/pick/auto-stack by time), move/rename/
  delete projects & albums.
- Slideshow and Light Table; histogram; statistics; search; date grouping.
- Robustness: schema-resilient readers; SQLite `immutable` reads; never ship
  `-journal` files.

### 2026-06-17 — Phase 1 complete + Phase 2 begun
- **Reader**: open `.aplibrary`, read projects/folders, masters, versions, and
  join them into `Photo` records.
- **Metadata**: parse EXIF/IPTC from `.apversion` plists (camera, lens,
  exposure, copyright); resolve cached thumbnails via `imageProxyState`.
- **Imaging**: ImageIO decode with orientation + downsampling (RAW-aware);
  full-resolution decode for export.
- **Albums & keywords**: read `RKAlbum`/`RKAlbumVersion` (with system-vs-user
  classification) and the `RKKeyword` vocabulary + per-photo keywords.
- **Filtering**: pure `PhotoFilter` (rating / flagged / edited / name) powering
  a filter bar in the app.
- **Export**: originals (byte copy) and rendered JPEG (resized) via `Exporter`;
  CLI `--export` command.
- **Writer**: rating/flag/colour-label writes that keep the SQLite catalog and
  the `.apversion` plist in sync, gated behind an explicit opt-in, plus a
  one-shot `backupCatalog()`.
- **App**: SwiftUI sidebar (projects + albums), thumbnail grid with filter bar,
  inspector (preview, rating, flag, metadata, keywords, open-in-external-editor).
- **CLI**: `openlens-cli` summary, `--list`, `--meta`, `--export`, `--rate`.
- **Quality**: dependency-free core; CI builds + runs a 22-test suite against a
  committed synthetic fixture (no personal photos).

### Notable fixes
- Open read-only catalogs with SQLite `immutable=1` to avoid spurious
  "attempt to write a readonly database" errors.
- Never commit SQLite `-journal`/`-wal`/`-shm`: a stray hot journal made a
  read-write open roll the catalog back to empty.
