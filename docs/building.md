# Building OpenLens

## Requirements
- macOS 13 (Ventura) or later
- Xcode 15+ (for the Swift 5.9 toolchain)

## From the command line (Swift Package Manager)

```bash
cd OpenLens
swift build                 # build everything
swift run openlens-cli <library.aplibrary>          # inspect a library
swift run openlens-cli <library.aplibrary> --list   # list all photos
swift run OpenLensApp                                # launch the SwiftUI app
OPENLENS_TEST_LIBRARY=<library.aplibrary> swift test # run tests
```

## In Xcode

`File ▸ Open…` and choose the `OpenLens` folder. Xcode reads `Package.swift`
and creates schemes for `openlens-cli`, `OpenLensApp`, and the tests. Pick a
scheme from the toolbar and press ⌘R.

## Note on the SwiftUI app target

`OpenLensApp` is currently an **SPM executable target** so the whole project
builds with one `swift run`. That's great for development, but an executable
target has no app bundle, so it lacks:
- an `Info.plist` (custom name, version, document types),
- an icon,
- sandbox / hardened-runtime entitlements (needed for the App Store and for
  security-scoped bookmarks to referenced masters),
- code signing for distribution.

When the app matures (Phase 6 in the roadmap), promote it to a real Xcode app
target:

1. In Xcode, `File ▸ New ▸ Target… ▸ macOS ▸ App`, name it `OpenLens`.
2. Remove its template `ContentView`/`App` files and instead add the existing
   `Sources/OpenLensApp` files (or move them under the app target).
3. Add a package/local dependency on `OpenLensKit`.
4. Configure bundle identifier, icon, and entitlements
   (`com.apple.security.files.user-selected.read-write` at minimum so the user
   can grant access to libraries outside the sandbox).

Keeping `OpenLensKit` as a separate library means the core logic stays testable
and reusable regardless of how the app is packaged.

## Working safely with real libraries

Always test writes against a **copy** of a library:

```bash
cp -R "~/Pictures/My Library.aplibrary" /tmp/test.aplibrary
OPENLENS_TEST_LIBRARY=/tmp/test.aplibrary swift test
```
