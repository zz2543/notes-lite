#!/bin/bash
# Renders glass/icon.html with the given JSON params to a PNG. Usage: render.sh out.png '{"shape":0,...}'
set -euo pipefail
cd "$(dirname "$0")"
OUT="$1"; PARAMS="${2:-{\}}"
HASH=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$PARAMS")
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --enable-unsafe-swiftshader --use-angle=swiftshader \
  --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 --virtual-time-budget=60000 \
  --screenshot="$OUT" "file://$PWD/icon.html#$HASH" >/dev/null 2>&1
echo "$OUT"
