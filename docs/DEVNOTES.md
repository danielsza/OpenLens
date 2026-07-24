# OpenLens — Developer Notes & Decision Log

A living memory of how OpenLens is built and *why*. Append to the log at the
bottom as work continues. New contributors (or a future session) should read
this top-to-bottom before making changes.

## Project goal
A modern, native macOS replacement for Apple Aperture that reads and **writes
real `.aplibrary` catalogs in place** — preserving projects, versions, ratings,
metadata, keywords, stacks, and (eventually) adjustments. See `README.md` and
`ROADMAP.md`.

## Architecture
- **`OpenLensKit`** — the core, **UI-free** (Foundation + SQLite3 + ImageIO +
  CoreGraphics only; no AppKit/SwiftUI). Everything testable lives here.
  - `Database/SQLiteDatabase.swift` — minimal SQLite wrapper.
  - `Models/` — `Project`, `PhotoMaster`, `PhotoVersion`, `Photo`, `Album`,
    `Keyword`, `Stack`, `Adjustment`, `ColorLabel`.
  - `Reader/` — `ApertureLibrary` (open + projects/masters/versions),
    `VersionMetadata` (EXIF/IPTC/thumbnails), `AlbumsKeywords`, `Stacks`,
    `Adjustments`, `PhotoFilter`.
  - `Writer/ApertureLibraryWriter.swift` — ratings/flags/labels + keywords,
    catalog backup.
  - `Imaging/ImageLoader.swift` — ImageIO decode (RAW-aware, oriented,
    downsampled) + full-res decode.
  - `Export/Exporter.swift` — originals + rendered JPEG.
- **`openlens-cli`** — inspection tool; proves the Kit on real libraries.
- **`OpenLensApp`** — SwiftUI app (SPM executable target for now; promote to a
  real Xcode app target later — see `docs/building.md`).
- **`OpenLensKitTests`** — runs against the committed synthetic fixture
  (`Tests/Fixtures/Mini.aplibrary`) via `OPENLENS_TEST_LIBRARY`.

## Conventions
- Keep `OpenLensKit` free of UI frameworks so it stays testable and reusable.
- Every new reader/writer feature gets tests that run against the fixture.
- Writes are **opt-in** (`allowWrites: true`) and must keep the SQLite catalog
  and the per-image `.apversion` plist in sync where both store the value.
- Tests that mutate **always operate on a temp copy** of the library.

## Hard-won crash lesson (2026-07-24, v0.1.5 SIGSEGV in the wild)
A shared `sqlite3*` connection used concurrently from the main thread (UI
reads) and background image loaders (`ImageCache.fullImage → olAdjustments`)
corrupted SQLite's heap. Fix: **open every connection with
`SQLITE_OPEN_FULLMUTEX`** (serialized mode) + cache `tableExists`. A
`concurrentPerform` regression test hammers a shared connection in CI.

- **2026-07-24** Polish pass from Daniel's screenshot: dark saturated RGB
  histogram (screen blend on near-black, hairline border), mini/small control
  sizes across filter bar + control bar + sliders, filmstrip pane height
  matched to content (kills grey banding), control-bar group dividers.

- **2026-07-24** From Daniel's feedback: blue divider line was the macOS focus
  ring on the focusable center column → min platform bumped to **macOS 14**
  and `.focusEffectDisabled()` applied. Control bar redesigned Aperture-style:
  centered, larger rating/flag/label cluster; in Split view it now sits
  directly UNDER THE VIEWER above the filmstrip. Thumbnail-size slider now
  resizes the filmstrip too (pane height follows). Rating/Sort pickers had
  collapsed under fixedSize+small — explicit widths restored.

- **2026-07-24** Filmstrip: breathing room at the bottom (padding 18) and an
  Aperture-style **hover scrubber** — a mini slider fades in over the strip on
  hover for jumping anywhere (only when >8 photos).

- **2026-07-24** Histogram fixed properly: blend mode must be applied **per
  channel** (container blendMode just alpha-stacks → pastel patchwork). Pure
  primaries + plusLighter on black = Aperture look. **Viewer focus + zoom**:
  clicking the canvas image focuses it (accent frame) and the control-bar
  slider becomes a 1–8× zoom (drag to pan, double-click resets); clicking any
  thumbnail returns the slider to thumbnail-size mode.

## Hard-won format lessons (see also docs/aperture-format.md)
1. **Dates** are seconds since 2001-01-01 (NSDate epoch), not Unix.
2. **Ratings/flags/labels live in two places**: `RKVersion` *and* the
   `.apversion` plist (`mainRating`, `iptcProperties.StarRating`). Keep synced.
3. **Open read-only with the `immutable=1` URI.** A plain read-only `SELECT`
   can fail with "attempt to write a readonly database" on some platforms.
4. **Never let `-journal`/`-wal`/`-shm` travel with a catalog.** A stray hot
   journal makes a read-**write** open roll the DB back to empty ("no such
   table"). Gitignored; the push helper also refuses to commit them.
5. `RKAlbumVersion`/`RKKeywordForVersion`/`RKStackContent` link by **`modelId`**
   (or version uuid for stacks), not always by uuid — check per table.
6. Thumbnails: `Thumbnails/<date>/<uuid>/thumb_<name>_1024.jpg`, paths recorded
   in `imageProxyState` of `Version-1.apversion`. `Previews/` may be empty.
7. Adjustments: one `RKImageAdjustment` row per edit; `name` is the class
   (`RKExposureAdjustment`…), `data` is usually an `NSKeyedArchiver` blob. We
   read names/enabled/order today; full parameter decode + Core Image rendering
   is the big Phase 3 task.
8. **Previews** (real-library verified): `Previews/<master date path>/
   <version uuid>/<version name>.jpg` — they are Aperture's *rendered output*,
   edits baked in, so preview-backed photos display correctly without decoding
   adjustments. Cached thumbs/previews are **already rotated** — apply
   `RKVersion.rotation` only when displaying the raw master (double-rotation
   bug otherwise); OpenLens rotations regenerate thumbnails.
9. **Faces** (`Database/apdb/Faces.db`): `RKDetectedFace` stores four corner
   points, normalized, bottom-left origin; corners can be swapped on rotated
   photos — take min/max of all four corners. Names in `RKFaceName.faceKey`.
10. **Keywords in plists** (real-library verified): top-level `keywords` =
    array of tab-joined leaf→ancestor paths; `iptcProperties.Keywords` =
    comma-joined flat string. Writer syncs DB + both plist forms.
11. `RKMaster.imageHash` is empty in real libraries — duplicate detection
    hashes file content (size-group → SHA-256). `RKNote` holds focus-point
    blobs, not user notes. GPS lives on `RKVersion.exifLatitude/Longitude`.

## Dev workflow used in these sessions (important!)
- The local git repo lives in the user's mounted folder; the sandbox **cannot
  delete files** there (FUSE restriction), so it can't run local `git commit`
  cleanly. **Commits are made via the GitHub REST API** (Git Data API: blobs →
  tree → commit → update ref) from a helper script. Binary files are
  base64-encoded; `-journal`/`-wal`/`-shm`/`.DS_Store`/`*.SECRET.txt` are
  never pushed.
- **Tokens**: the original all-scopes PAT was exposed and rotated (2026-07-23);
  Daniel then supplied a fresh PAT mid-session. When the sandbox has no valid
  token, the fallback workflow is: Claude edits files locally, Daniel runs
  `git add -A && git commit && git push`. When a token exists, Claude pushes
  via the API helper and can also manage repo secrets (sealed-box PUT).
  If Daniel's local HEAD goes stale vs API pushes: `git fetch origin &&
  git reset origin/main` (keeps working tree), then commit/push.
- **CI is the compiler/test oracle.** The sandbox has no Swift toolchain, so we
  push and let GitHub Actions (`.github/workflows/ci.yml`, macOS runner, Xcode
  15.x) build + run the suite. Always wait for green before moving on. CI also
  uploads a runnable OpenLens.app artifact; `release.yml` publishes GitHub
  Releases (+ Sparkle appcast) on `v*` tags.
- Local builds: `bash scripts/build_app.sh` → `build/OpenLens.app` + Desktop
  copy (bundles Sparkle.framework, portable rpath).
- The fixture is generated by a script (kept outside the repo in the session);
  if you change the schema the reader queries, **regenerate the fixture** to add
  the new columns/rows or CI will fail with "no such column".
- Real validation library: `../babcia.aplibrary` (676MB, expendable copy) —
  use it (via Python mirrors of the Swift queries) to verify format assumptions
  before coding. `../test.aplibrary` is the small expendable one.
- **Sparkle keys (2026-07-23)**: public key committed at
  `scripts/sparkle_public_key.txt`; private key = base64 Ed25519 seed, local at
  `scripts/sparkle_private_key.SECRET.txt` (gitignored) AND stored as the
  `SPARKLE_PRIVATE_KEY` GitHub Actions secret. Release workflow signs update
  zips with PyNaCl (plain Ed25519 over archive bytes — Sparkle-compatible).

## Testing locally (for the user)
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # need full Xcode, not CLT
OPENLENS_TEST_LIBRARY=Tests/Fixtures/Mini.aplibrary swift test
```
`swift test` needs full Xcode (XCTest); Command Line Tools alone give
"no such module 'XCTest'".

## Decision log
- **2026-06-17** Chose native macOS / Swift + SwiftUI (best RAW/Core Image,
  external-editor handoff, native feel). Mac-only is acceptable for an Aperture
  replacement.
- **2026-06-17** Zero third-party dependencies in the core (system SQLite3 +
  Foundation + ImageIO). Keeps builds simple and the data layer auditable.
- **2026-06-17** SwiftUI app is an SPM executable target for now (one
  `swift run`); promote to a real `.app` target in Phase 6 for bundle/icon/
  entitlements/sandbox.
- **2026-06-17** Read with `immutable=1`; never commit SQLite side-files (both
  after debugging the readonly-write and empty-catalog failures).
- **2026-06-17** Committed a *synthetic* fixture (no personal photos) so CI runs
  real read/write paths; tests are env-gated and skip without it.
- **2026-06-17** Keyword writes are catalog-only for now (that's what we read);
  mirroring keywords into the `.apversion` plist is a TODO.
  *(Superseded 2026-07-23: format decoded from the real library; keyword writes
  now sync DB + plist `keywords` array + `iptcProperties.Keywords`.)*
- **2026-07-23** Auto-updates: Sparkle 2 via SPM (app target only). Release
  signing uses plain Ed25519 (PyNaCl) in CI instead of Sparkle's CLI tools —
  same signature Sparkle verifies, but no dependence on their key-file format.
- **2026-07-23** Aperture's rendered Previews are the display path for edited
  photos; adjustment *decoding* is only needed for re-editing (still awaiting
  an edited sample library).

## Running progress log
- **2026-06-17** Phase 0 scaffold; repo + CI; reader (projects/masters/
  versions); CLI; SwiftUI shell; guarded writer; README/ROADMAP/format docs.
- **2026-06-17** Phase 1: EXIF/IPTC + thumbnail resolution; ImageIO/RAW decode
  wired into grid + inspector; albums/smart-albums + keywords; synthetic
  fixture + real CI coverage; export (originals + rendered JPEG); filter bar.
- **2026-06-17** Phase 2: writer hardened + tested (ratings/flags/labels keep
  DB + plist in sync; `backupCatalog()`); keyword add/remove/set with tests.
- **2026-06-17** Phase 1: stacks reading (`RKStackContent`/`RKStackState`).
- **2026-06-17** Phase 3 groundwork: read adjustments (type/enabled/order +
  best-effort numeric params); shown in the inspector. Rendering still TODO.
- **2026-06-17** Added `LibraryStatistics` (counts + rating histogram) + CLI
  stats output.
- **2026-06-17** Added free-text `search()` across name + keywords + camera/lens
  (AND semantics).
- **2026-06-17** Added folder/project tree (`folderHierarchy()` /
  `projectNavigator()`) and a nested sidebar via `OutlineGroup`.
- **2026-06-17** Trash: reversible `moveToTrash`/`restoreFromTrash` (DB + plist)
  and `trashedPhotos()` reader. Permanent delete intentionally not implemented
  yet. Suite at 45.
- **2026-06-17** Added in-app name filter field and CLI `--search`.

- **2026-06-17** CI now builds release binaries + a runnable `OpenLens.app` and
  uploads them as artifacts (see docs/building.md). Added date grouping
  (`[Photo].grouped(by:)`).
- **BLOCKED:** decoding real adjustment *parameters* needs a library with actual
  edits — the test library is an unedited import (0 `RKImageAdjustment` rows), so
  the `NSKeyedArchiver` blob format can't be reverse-engineered yet. Ask Daniel
  for an edited `.aplibrary` (a copy) to proceed with adjustment rendering.

- **2026-06-17** Verified the writer's operations (rating + plist/IPTC, keyword
  create/assign, trash) against a COPY of the *real* `test.aplibrary` via a
  Python replay — confirms our SQL + binary-plist edits work on genuine data,
  not just the synthetic fixture.
- **2026-06-17** Added guarded permanent delete: `permanentlyDelete(versionUuid:)`
  and `emptyTrash()` (removes catalog rows; deletes master row + file + version
  plist folder when no version references the master). Irreversible.

- **2026-06-19** Aperture-style **dark UI**: charcoal `Theme`, toolbar
  Grid/Split/Viewer toggle, Split = viewer + filmstrip, big `ImageViewer`,
  bottom `ControlBar` (rating/flag/colour labels/thumbnail-size), shared
  `PhotoThumbnail`, `ImageCache` (NSCache) for scroll perf, dark sidebar +
  inspector with Info/Adjustments tabs, arrow-key photo navigation. UI is
  compile-checked via CI only — Daniel reviews the look and sends screenshots
  to refine greys/spacing.

- **2026-06-19** Matched Aperture's reference screenshot: light-grey chrome +
  dark photo area palette; merged the left panel into a single **tabbed
  inspector** (Library / Info / Adjustments) like Aperture (two-pane layout);
  moved the Grid/Split/Viewer switcher to the top-right.

- **2026-06-19** Library session behavior like Aperture: remember last library
  (UserDefaults) and auto-open on launch; hold **Option** at launch for the
  chooser; **Open / Switch Library…** (⌘O) and **Close Library** (⇧⌘W) menu
  commands; Close returns to the chooser without quitting. (New-library
  creation still TODO — we can't author an `.aplibrary` from scratch yet.)

- **2026-06-19** Sidebar **Library** section (Photos/Flagged/Rejected/Trash smart
  sources) like Aperture. Reject now supported (rating -1; writer clamp -1...5,
  `9` key, control-bar reject button); populates the Rejected source.

- **2026-06-19** New-library creation: `ApertureLibraryCreator.createLibrary`
  authors a fresh `.aplibrary` (package + Info.plist + `Library.apdb` with the
  RK* tables OpenLens reads + system folders/smart albums). Wired to **New
  Library…** (⌘N). `SQLiteDatabase` gained a `create` mode. Note: authors the
  tables OpenLens uses, not all ~33 of Aperture's — fine for OpenLens; full
  Aperture-authoring is a later refinement.

- **2026-06-19** Structure writes: `createProject`, `createAlbum`,
  `addVersion(_:toAlbumUuid:)` on the writer (+ tests on a created library).
  Wired to a toolbar "+" menu (New Project / New Album) with a name prompt.

- **2026-06-19** Import: `importImage(at:intoProject:)` copies a file into
  `Masters/<date>/<stamp>/` and authors `RKMaster`/`RKVersion` (managed master).
  Wired to "+" menu → Import Photos…. Thumbnail/EXIF-plist generation on import
  is still TODO (reader falls back to decoding the master). Tested end-to-end on
  a created library.

- **2026-06-19** Import now also generates a **cached JPEG thumbnail** and a
  minimal **Version-1.apversion** (real EXIF via `ImageLoader.exifSummary` +
  proxy paths), so imported photos browse fast and show metadata. Reader's
  `parseMetadata` now prefers a direct `FNumber` (how we write imports) over the
  APEX `ApertureValue` (how Aperture stored it).

- **2026-06-19** GPS/location: read `RKVersion.exifLatitude/exifLongitude`
  (`PhotoVersion.latitude/longitude`), shown in the Info tab; extracted from
  EXIF on import; added the columns to the fixture + creator schema.

- **2026-06-19** Duplicate Version: `duplicateVersion` writer method (new version
  row sharing the master) + Photo ▸ Duplicate Version (⌘D); tested.

- **2026-06-19** CLI authoring: `--create`, `--new-project`, `--import`,
  `--duplicate`. App trash actions: Photo ▸ Move to Trash (⌘⌫) / Put Back /
  Empty Trash… (with confirm).

- **2026-06-19** Resilience: optional readers (stacks/albums/keywords/
  adjustments) guard on `tableExists` so libraries from other Aperture builds
  (missing a table) degrade to empty instead of crashing. + test.

- **2026-06-19** Browser sort (Date/Name/Rating/File Name, asc/desc) —
  `[Photo].sorted(by:)` + filter-bar control. + test.

- **2026-06-19** Multi-selection: Cmd/Shift click, batch rating/flag/label/reject
  (control bar + keyboard apply to the whole selection), batch move-to-trash,
  selection count in the status bar.

- **2026-06-19** Export presets (Aperture-style): `ExportSettings` (format
  JPEG/PNG/TIFF/originals, max long-edge, quality, DPI) + `Watermark` (text or
  image, position, opacity) rendered via CoreGraphics/CoreText; `Exporter`
  settings API + tests; an Export sheet (File ▸ Export…, ⇧⌘E) for selection or
  all-shown.

- **2026-06-19** Export sheet gains a **logo/image watermark** picker (choose
  image + scale slider) alongside text; watermark default position Bottom Center.

- **2026-06-19** Export dialog now persists settings (@AppStorage) across
  launches and adds a Custom long-edge size field.

- **2026-06-19** Keyword editing in the Info inspector: removable keyword chips
  + add-keyword field (store.addKeyword/removeKeyword on the tested writer).

- **2026-06-19** Rename project/album: writer methods + tests + sidebar
  right-click ▸ Rename… . Window title shows the open library name.

- **2026-06-19** Structure/stack writers: createStack/breakStack/setStackPick,
  moveVersion(toProject), deleteAlbum, deleteProject (versions→trash). + tests.

- **2026-06-19** Slideshow (auto-advance, play/pause, interval, nav) and Light
  Table (freeform drag canvas, resize, auto-arrange) — View menu (⌥⌘S / ⌥⌘L).

- **2026-06-19** IPTC metadata editing: read+write caption/title/byline/
  copyright (`setIPTC` patches the `.apversion` plist); editable fields in the
  Info inspector. + test.

- **2026-06-19** Histogram: `ImageLoader.histogram` (RGB + luminance) + a
  luminance histogram in the Adjustments inspector. + test.

- **2026-06-19** Rotate: writer setRotation/rotate + Photo ▸ Rotate Left/Right
  (⌘[ / ⌘]); ImageCache bakes `RKVersion.rotation` into displayed images
  (cache keyed by rotation). + test.

- **2026-06-19** Native smart albums: save the current filter as a named smart
  album (File ▸ Save Filter as Smart Album…), persisted (UserDefaults/Codable),
  listed in the sidebar; PhotoFilter is now Codable.

- **2026-06-19** Auto-stack by time: `[Photo].autoStackGroups(gapSeconds:)` +
  Photo ▸ Auto-Stack by Time (stacks runs of close-in-time photos). + test.
  This completes the "buildable without input" Aperture parity list.

- **2026-06-20** Consistency checker (`checkConsistency`) + **repair** (delete
  dangling rows, regenerate thumbnails/plists, mark missing masters, trash
  orphans) + CLI `--verify [--repair]`; viewer prefetches neighbour images.
  NOTE: GitHub PAT was rotated — sandbox can no longer push. Workflow now:
  Claude writes locally, Daniel commits/pushes (`git reset origin/main` first
  if HEAD is stale, then add/commit/push).

- **2026-06-20** Loupe magnifier in the viewer (` key toggles; 2.5× circular
  magnifier follows the cursor). Export now **preserves EXIF/TIFF/IPTC/GPS
  metadata** in rendered files (toggle in Export dialog, on by default) + test.

- **2026-07-23** Validated the whole reader against a REAL library
  (babcia.aplibrary, 676MB, 263 masters, 2006–2019, iPhoto-migrated): all
  versions join, 30/30 plists matched, 30/30 thumbnails, zero dangling rows.
  It has ratings/keywords/previews but **no adjustments** (still need an edited
  library for that).
- **2026-07-23** **Previews support**: layout verified as
  `Previews/<master date path>/<version uuid>/<version name>.jpg` (27/27 real
  previews resolve). New `previewURL(for:)` + `viewerImageURL(for:)`; the big
  viewer now prefers previews. **KEY INSIGHT: previews are Aperture's rendered
  output, so edited photos display with their edits applied even before we can
  decode adjustments.** + test.

- **2026-07-23** Inspector shows what the viewer displays (preview vs master);
  statistics/CLI count previews; grid shows a wrench badge on edited photos.

- **2026-07-23** App icon (programmatically drawn aperture blades →
  .icns in CI bundle) and a **Release workflow**: pushing a tag `v*` runs
  tests, builds OpenLens.app, and publishes a GitHub Release with the zip +
  CLI attached. To cut v0.1.0: `git tag v0.1.0 && git push origin v0.1.0`.

- **2026-07-23** Duplicate detection (`findDuplicates`: size-group → SHA-256,
  one representative per master; Aperture's imageHash is empty in real
  libraries) + CLI `--duplicates` + test. **Places map** (MapKit) of geotagged
  photos with clickable pins — View ▸ Places (⌥⌘P).

- **2026-07-23** Folder-tree import: `importFolderTree(at:)` — every folder with
  images becomes a project; recursive; skips dotfolders/.aplibrary; "+" menu ▸
  Import Folder as Projects… and CLI `--import-tree`. + test.
- **2026-07-23** Duplicates UI: View ▸ Find Duplicates — thumbnail groups with
  per-copy "Trash this copy" buttons; rescans after each trash.

- **2026-07-23** **Faces**: read `Faces.db` (`RKDetectedFace` + `RKFaceName`) —
  595 real detections validated 587/587 after normalizing via min/max of all
  four corners (rotated photos store swapped corners; bottom-left-origin →
  top-left). Viewer overlays face boxes + names, toggled with **F**. + tests.

- **2026-07-23** Video support: `PhotoMaster.isVideo`; viewer plays VIDT
  masters via AVKit; grid shows a play badge + AVAssetImageGenerator frame
  thumbnails; import detects video extensions (type VIDT); folder import
  accepts videos. Docs (CHANGELOG/README/STATUS) refreshed.

- **2026-07-23** Fixes from Daniel's first real-library screenshots:
  (1) `selectedPhoto` now also searches the trash — selecting in the Trash view
  drives viewer/inspector/control bar; (2) filter bar compacted (icon toggles,
  fixedSize pickers, non-wrapping status) so nothing truncates at narrow
  widths; (3) **double-rotation fixed** — Aperture's cached thumbs/previews are
  already rotated, so version rotation is applied only when displaying the raw
  master. Rotating in OpenLens now regenerates the cached thumbnails with the
  rotation baked in (`refreshThumbnail`), so browsing reflects it immediately.
  Remaining edge: full-size *previews* of rotated photos aren't regenerated
  (we can't re-render edits), so the viewer may show the old orientation for
  the few preview-backed photos rotated in OpenLens.

- **2026-07-23** Keyword plist mirroring: decoded Aperture's real format from
  babcia (top-level `keywords` = tab-joined leaf→ancestor paths;
  `iptcProperties.Keywords` = comma-joined flat list) and keyword writes now
  sync DB + plist + IPTC. Notes table turned out to be focus-point blobs only —
  no user-notes feature needed. + test.

- **2026-07-23** **Auto-updates via Sparkle 2**: SPM dependency (app target
  only), `Check for Updates…` menu, Sparkle.framework bundled by build script +
  CI + release workflow (portable rpath), `SUFeedURL` points at
  releases/latest/download/appcast.xml, release workflow signs the zip with the
  `SPARKLE_PRIVATE_KEY` secret and publishes the appcast. Daniel's one-time key
  setup in docs/updates.md. Updates install without Gatekeeper nags (only the
  first browser-downloaded install needs right-click ▸ Open).

- **2026-07-23** **ADJUSTMENT EDITING SHIPPED (OpenLens-native)**: realized we
  don't need Aperture's blob format for *new* edits — defined `OLAdjustments`
  (exposure/contrast/saturation/temp/tint/highlights/shadows/sharpness), stored
  as JSON in an `RKImageAdjustment` row named `OLAdjustmentsV1`; rendered with
  Core Image (`AdjustmentRenderer`); live-preview sliders in the Adjustments
  tab with Save/Reset; viewer + export + regenerated thumbnails all apply the
  look; hasAdjustments synced DB+plist. Aperture's own edits still display via
  previews and are listed read-only. Decoding Aperture's blobs (for re-editing
  old edits) remains blocked on an edited sample library. + tests (render
  brightness delta, save/load/clear round-trip).

- **2026-07-23** UI matched to Daniel's Aperture 3 reference (Wikipedia shot):
  **RGB histogram** (additive channel overlay), **adjustment bricks** (White
  Balance/Exposure/Enhance/Highlights & Shadows/Sharpen) shared between the
  inspector tab and a new **floating Adjustments HUD** over the viewer (H key
  or control-bar button; ultraThinMaterial dark panel); viewer image gets a
  shadow + hairline frame bookend; filmstrip gets edge fades + top hairline.
  Edit state centralized in the store (`editParams`/`savedEditParams`).

- **2026-07-23** Missing-features push: **Compare view** (two-up, synced
  zoom/pan, ⌥⌘C), **Loupe zoom levels** 50%–1600% (= / - keys, % badge),
  **Print** (⌘P, aspect-fit, auto orientation). **Version convention (per
  Daniel, pitcrew-style): ALWAYS BUMP** — dev builds stamp `tag.commitsSince`
  (e.g. 0.1.2.5) and every feature batch gets a new release tag (Claude tags
  via API). Scoped out (do NOT build): books, web galleries, FTP publishing.
  Deferred pending real hardware/data: tethering, Raw Fine Tuning (CIRAWFilter),
  referenced-master alias resolution (needs a referenced sample library).

- **2026-07-23** Batch for v0.1.3: **full-screen editing mode** (F toggles,
  Esc exits; hides left panel + filter bar; face boxes moved to **B**),
  **thumbnail context menus** (rating/flag/label/duplicate/rotate/editor/
  Finder/trash-or-put-back), **filter-bar search matches keywords** too
  (preloaded keywordsByVersion map — no per-photo queries). + test.

- **2026-07-23** **Referenced imports** ("keep files in place"): OpenLens
  references store the ABSOLUTE path in `imagePath` + fileIsReference=1; reader
  resolves absolute-path references (legacy Aperture alias blobs still not
  decoded — those are skipped by the checker rather than flagged). "+" menu ▸
  Import as Referenced…, CLI `--import ... --referenced`. **Vault backups**:
  `createVault(in:)` copies the package + verifies the copy; File ▸ Back Up
  Library…, CLI `--vault <dir>`. + tests for both.

- **2026-07-24** v0.1.5 batch: folder-import runs in the background with a
  progress HUD (capsule overlay); **HEIC export** (quality slider applies).

### Current state (as of 2026-07-23)
- ~95 tests, green in CI; near-complete Aperture parity for viewing/organizing,
  validated against a real 676MB library (babcia). Daniel is actively testing
  local builds and reporting via screenshots (that loop caught & fixed trash
  selection, filter-bar truncation, and double-rotation).
- Features: see docs/STATUS.md — browse (Grid/Split/Viewer, filmstrip, Loupe,
  faces overlay, histogram), organize (everything incl. stacks/smart albums/
  multi-select), Faces, Places, video playback, import (files/folder-trees),
  duplicates, export (full presets + watermarks + metadata), consistency
  verify/repair, new-library authoring, Slideshow, Light Table, CLI for all.
- Distribution: CI artifact app + `scripts/build_app.sh` local builds +
  Release workflow on `v*` tags with **Sparkle auto-updates** (keys installed;
  `SPARKLE_PRIVATE_KEY` secret set 2026-07-23).

### Next up
1. **Tag v0.1.0** — first auto-updatable release (everything is in place).
2. **Adjustment decoding** — STILL BLOCKED on an edited sample library
   (docs/APERTURE-TEST-CHECKLIST.md). Display already works via Previews.
3. UI polish from Daniel's screenshots as he uses the app.
4. Later: Developer ID signing/notarization (kills first-install Gatekeeper
   warning); promote app to a real Xcode target; full Aperture-schema
   authoring; referenced-master alias resolution.
