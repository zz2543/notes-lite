#!/bin/bash
# Renders twain-icon.svg to a 1024px PNG with headless Chrome. Usage: render.sh [in.svg] [out.png]
set -euo pipefail
cd "$(dirname "$0")"
IN="${1:-twain-icon.svg}"; OUT="${2:-twain-icon-1024.png}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"
printf '<html><body style="margin:0;background:transparent">%s</body></html>' "$(cat "$IN")" > "$TMP/i.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --screenshot="$OUT" "file://$TMP/i.html" >/dev/null 2>&1
rm -rf "$TMP"
echo "$OUT"
