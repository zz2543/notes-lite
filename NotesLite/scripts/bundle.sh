#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/NotesLite.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NotesLite" "$APP/Contents/MacOS/NotesLite"
for resource in "$BIN"/NotesLite_*.bundle; do
  if [ -d "$resource" ]; then cp -R "$resource" "$APP/Contents/Resources/"; fi
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NotesLite</string>
<key>CFBundleDisplayName</key><string>留白</string>
<key>CFBundleIdentifier</key><string>local.noteslite.desktop</string>
<key>CFBundleExecutable</key><string>NotesLite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$PWD/$APP"
