# OpenLens Roadmap

A long project, built in phases. Each phase is independently useful and keeps
the app shippable. The guiding rule: **never risk a user's library** — reads
first, writes only when proven, always reversible.

## Phase 0 — Foundations ✅ (this scaffold)
- [x] Reverse-engineer and document the `.aplibrary` format.
- [x] Dependency-free SQLite wrapper.
- [x] Read projects, masters, versions; join into `Photo` records.
- [x] CLI inspector (`openlens-cli`).
- [x] SwiftUI shell: project sidebar, thumbnail grid, inspector.
- [x] Guarded writer for ratings/flags/colour labels (DB + plist in sync).
- [x] Unit tests against a real library.

## Phase 1 — Solid browsing
- [ ] Load rendered **previews/thumbnails** from `Previews/`+`Thumbnails/`
      (via `imageProxyState`) instead of decoding full masters.
- [ ] RAW + wide-gamut decode via **ImageIO / Core Image**.
- [ ] Correct orientation/rotation handling.
- [ ] Albums and smart albums (`RKAlbum`), not just projects.
- [ ] Keywords display (`RKKeyword` / `RKKeywordForVersion`).
- [ ] Stacks (`RKStackState` / `RKStackContent`).
- [ ] Fast scrolling for large libraries (lazy loading, image cache).

## Phase 2 — Metadata editing (safe writes)
- [ ] Hardened rating/flag/label writes with automatic library backup.
- [ ] Keyword add/remove.
- [ ] Update `Properties.apdb` search index and append `History` entries so
      edits are consistent with Aperture's own bookkeeping.
- [ ] Batch operations across selections.
- [ ] Undo/redo.

## Phase 3 — Adjustments (non-destructive)
- [ ] Parse existing `RKImageAdjustment` parameters and render an approximation
      with Core Image.
- [ ] Editable basic adjustments: exposure, contrast, saturation, white
      balance, highlights/shadows, crop, straighten.
- [ ] Write adjustments back in a form Aperture *or* OpenLens can re-render.
- [ ] (Stretch) match Aperture's rendering for existing edits.

## Phase 4 — Import / export / external edit
- [ ] Export originals and rendered JPEG/TIFF/PNG with embedded metadata.
- [ ] Export presets (size, quality, naming, watermark).
- [ ] "Open in external editor" round-trip that re-imports the result as a new
      version.
- [ ] Import new files into existing projects (the riskiest write path — last).

## Phase 5 — Referenced masters & robustness
- [ ] Resolve referenced masters via `fileAliasData` / `RKVolume`.
- [ ] Relink moved/missing masters.
- [ ] Library consistency checker / repair.
- [ ] Vault-style backups.

## Phase 6 — Polish & distribution
- [ ] Proper Xcode app target: bundle, icon, sandbox entitlements.
- [ ] Faces/places (optional).
- [ ] Preferences, keyboard shortcuts matching Aperture muscle memory.
- [ ] Notarised build / distribution.

## Non-goals (for now)
- Cloud sync, web galleries, book/slideshow layout.
- Importing from Lightroom / Capture One catalogs.

## Engineering principles
- The catalog has two sources of truth (SQLite + per-image plists) — **keep
  them in sync** on every write.
- Test every writer against a throwaway copy before it touches real data.
- Keep `OpenLensKit` UI-free so it can be scripted, tested, and reused.
