# Where things stand (morning note)

Hi Daniel — here's a quick orientation to what got built overnight and where to
pick up.

## What works now
- Open a real `.aplibrary` and browse **projects** and **user albums**.
- **Thumbnail grid** with a **filter bar** (rating / flagged / edited).
- **Inspector**: preview image, star rating, flag, EXIF (camera/lens/exposure),
  copyright, keywords, and "Open in External Editor".
- **Editing**: set rating / flag / colour label, written safely to both the
  SQLite catalog and the per-image `.apversion` plist (toggle "Save edits" in
  the toolbar to persist).
- **Export**: originals or rendered JPEGs.
- **CLI**: `swift run openlens-cli <library> --list --meta`,
  `--export <dir> [--rendered --size N]`, `--rate <versionUuid> 0-5`.

## How to run
```bash
cd OpenLens
swift run OpenLensApp                       # the app
swift run openlens-cli <library.aplibrary> --list --meta
OPENLENS_TEST_LIBRARY=Tests/Fixtures/Mini.aplibrary swift test
```
Open the folder in Xcode to develop (it reads `Package.swift`).

## Safety reminders
- Editing is **off by default** in the app; turn on "Save edits" only on a copy
  until you trust it.
- The Kit always backs writes with `backupCatalog()` available, and tests run
  against a throwaway copy — but back up your real library first.

## Good next steps
1. **Full-size previews + an image cache** so big libraries scroll smoothly.
2. **Stacks** (`RKStackState` / `RKStackContent`).
3. **Keyword editing** (add/remove), then batch metadata edits + undo.
4. Begin **adjustments** (Phase 3): parse `RKImageAdjustment` and approximate
   with Core Image.
5. Promote `OpenLensApp` to a real Xcode app target (bundle/icon/entitlements)
   so it can open libraries outside the sandbox — see `docs/building.md`.

## Housekeeping
- Rotate the GitHub PAT shared in chat (used only to create/push the repo).
- To sync your local clone to everything pushed overnight:
  `git fetch origin && git reset --hard origin/main`.
