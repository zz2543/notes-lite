#!/bin/bash
# Builds Plume.app into ./build. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Plume"
APP="build/Plume.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Plume"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Plume</string>
  <key>CFBundleDisplayName</key><string>Plume</string>
  <key>CFBundleIdentifier</key><string>app.plume.notes</string>
  <key>CFBundleExecutable</key><string>Plume</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
