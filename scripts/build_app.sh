#!/bin/bash
# Builds a runnable OpenLens.app locally (same steps as CI).
# Usage:  bash scripts/build_app.sh
# Output: build/OpenLens.app  (also copied to your Desktop)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Building release binaries…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ Drawing app icon…"
mkdir -p build OpenLens.iconset
swift scripts/make_icon.swift build/icon_1024.png 1024
for sz in 16 32 64 128 256 512; do
  sips -z $sz $sz build/icon_1024.png --out OpenLens.iconset/icon_${sz}x${sz}.png >/dev/null
  dbl=$((sz*2))
  sips -z $dbl $dbl build/icon_1024.png --out OpenLens.iconset/icon_${sz}x${sz}@2x.png >/dev/null
done
cp build/icon_1024.png OpenLens.iconset/icon_512x512@2x.png
iconutil -c icns OpenLens.iconset -o build/OpenLens.icns
rm -rf OpenLens.iconset

echo "▸ Assembling OpenLens.app…"
APP="build/OpenLens.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenLensApp" "$APP/Contents/MacOS/OpenLens"
cp "$BIN/openlens-cli" "$APP/Contents/MacOS/openlens-cli"
cp build/OpenLens.icns "$APP/Contents/Resources/OpenLens.icns"

# Bundle Sparkle.framework (auto-updates) and make its rpath portable.
SPARKLE_FW="$(find .build -type d -name "Sparkle.framework" -path "*macos*" | head -1 || true)"
if [ -n "$SPARKLE_FW" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/OpenLens" 2>/dev/null || true
fi

# Sparkle public key for verifying updates (commit yours to scripts/sparkle_public_key.txt).
SU_PUBLIC_KEY=""
[ -f scripts/sparkle_public_key.txt ] && SU_PUBLIC_KEY="$(tr -d '[:space:]' < scripts/sparkle_public_key.txt)"

# Version = latest tag (falls back for tag-less checkouts).
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
[ -z "$VERSION" ] && VERSION="0.0.0"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OpenLens</string>
  <key>CFBundleDisplayName</key><string>OpenLens</string>
  <key>CFBundleIdentifier</key><string>com.openlens.app</string>
  <key>CFBundleExecutable</key><string>OpenLens</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleIconFile</key><string>OpenLens</string>
  <key>SUFeedURL</key><string>https://github.com/danielsza/OpenLens/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>${SU_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Replace (never merge into) any existing Desktop copy — cp -R into an
# existing .app would nest the new bundle inside the old one.
rm -rf "$HOME/Desktop/OpenLens.app"
cp -R "$APP" "$HOME/Desktop/OpenLens.app" 2>/dev/null && DESK=" and ~/Desktop/OpenLens.app" || DESK=""
echo
echo "✅ Done: $(pwd)/$APP$DESK"
echo "   First launch: right-click ▸ Open (unsigned build)."
