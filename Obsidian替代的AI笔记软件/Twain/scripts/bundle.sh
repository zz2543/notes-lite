#!/bin/bash
# Builds Twain.app into ./build. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Twain"
APP="build/Twain.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN" "$APP/Contents/MacOS/Twain"
# The agent-facing command. Built as twain-cli so it can't clash with Twain on a case-insensitive disk.
cp "$(dirname "$BIN")/twain-cli" "$APP/Contents/Helpers/twain"
cp -R "$(dirname "$BIN")/Twain_Twain.bundle" "$APP/Contents/Resources/"
# Source art lives in design/icon (twain-icon.svg → render.sh → Twain.icns).
cp design/icon/Twain.icns "$APP/Contents/Resources/Twain.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Twain</string>
  <key>CFBundleDisplayName</key><string>Twain</string>
  <key>CFBundleIdentifier</key><string>app.twain.notes</string>
  <key>CFBundleExecutable</key><string>Twain</string>
  <key>CFBundleIconFile</key><string>Twain</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>LSHasLocalizedDisplayName</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>app.twain.notes</string>
    <key>CFBundleURLSchemes</key><array><string>twain</string></array>
  </dict></array>
</dict>
</plist>
PLIST
# The name is 共笔 in Chinese and Twain everywhere else (docs/naming.md).
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
printf 'CFBundleName = "共笔";\nCFBundleDisplayName = "共笔";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
printf 'CFBundleName = "Twain";\nCFBundleDisplayName = "Twain";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
codesign --force --sign - "$APP/Contents/Helpers/twain" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
