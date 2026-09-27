#!/bin/bash
# Render icon.html with JSON params to a 1024px PNG. Usage: render.sh out.png '{"bg":"..."}'
set -euo pipefail
cd "$(dirname "$0")"
HASH=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "${2:-{\}}")
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --virtual-time-budget=3000 --screenshot="$PWD/$1" "file://$PWD/icon.html#$HASH" >/dev/null 2>&1
echo "$1"
