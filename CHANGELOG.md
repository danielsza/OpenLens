# Changelog

All notable changes to OpenLens. Dates are ISO-8601.

## [Unreleased]

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
