# Where things stand

Quick orientation for Daniel (and future sessions). Updated 2026-07-23.

## What works — near-complete Aperture parity for viewing & organizing
- **Open real `.aplibrary` catalogs in place** — validated against a real
  676MB library; consistency checker reports zero issues on it.
- **Browse**: Aperture-style UI (Grid / Split / Viewer + filmstrip), tabbed
  Library/Info/Adjustments inspector, Loupe (`), face boxes (F), histogram,
  filter bar, sort, search, smart albums, multi-select, keyboard shortcuts.
- **Organize**: projects (nested), albums, stacks (create/break/pick/auto),
  ratings incl. Reject, flags, colour labels, keywords, IPTC, rotate, trash
  (move/restore/empty/permanent), move/rename/delete, duplicate version.
- **Faces** (rectangles + names) and **Places** (map of geotagged photos).
- **Import**: files or whole folder trees (folders → projects); thumbnails,
  EXIF and GPS generated on import. **Duplicates** finder with review UI.
- **Export**: JPEG/PNG/TIFF/originals, size presets + custom, DPI, quality,
  filename suffix, text/logo watermark (Bottom Center default), metadata
  carry-over, persisted settings.
- **Author**: create new libraries, Slideshow, Light Table, statistics,
  `--verify --repair`, full CLI for everything.
- **Distribution**: CI builds a runnable OpenLens.app (with icon) on every
  push; tagging `v*` publishes a GitHub Release automatically.

## How to run
Download **OpenLens-app** from Actions artifacts (or a Release), right-click ▸
Open. Or: `swift run OpenLensApp`. Tests: 80+ green in CI on every push.

## The two remaining gaps (both need Daniel)
1. **Adjustment editing** — decoding `RKImageAdjustment` blobs needs a small
   library with real edits (see docs/APERTURE-TEST-CHECKLIST.md). NOTE: edited
   photos already *display* correctly via rendered Previews.
2. **Visual polish** — screenshots of the current build to calibrate.

## Workflow note
GitHub PAT was rotated; the sandbox writes code locally and Daniel publishes:
`git add -A && git commit -m "..." && git push`. CI status is readable publicly.
