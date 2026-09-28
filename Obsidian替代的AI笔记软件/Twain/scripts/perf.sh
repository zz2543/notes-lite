#!/bin/bash
# Measures Twain on a copy of a vault and appends the numbers to docs/perf-log.md.
# Usage: scripts/perf.sh <vault> [label] [notes]
#   <vault>  a vault to copy (never touched itself; the run edits and saves in the copy)
#   label    a name for this run in the log, e.g. "baseline" or "d1"
#   notes    how many notes to open in a row (default 44)
# The window appears without taking the keyboard. Numbers are from an optimized build that
# still has the debug scenarios compiled in.
set -uo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?usage: scripts/perf.sh <vault> [label] [notes]}"
LABEL="${2:-$(git rev-parse --short HEAD)}"
COUNT="${3:-44}"
swift build -c release -Xswiftc -DDEBUG --build-path .build-opt >/dev/null || exit 1
BIN="$(swift build -c release -Xswiftc -DDEBUG --build-path .build-opt --show-bin-path)"

WORK="$(mktemp -d)"
cp -R "$SRC" "$WORK/vault"
SOCK="$HOME/Library/Application Support/Twain/run/perf-$$.sock"
PORT=$((27800 + $$ % 500))
trap 'rm -f "$SOCK"; rm -rf "$WORK"' EXIT

OUT="$(TWAIN_SNAPSHOT_VAULT="$WORK/vault" TWAIN_BACKGROUND=1 TWAIN_SOCK="$SOCK" TWAIN_HTTP_PORT=$PORT \
       TWAIN_SCENARIO="stress:$COUNT" TWAIN_EXIT=1 "$BIN/Twain" 2>&1 | grep '^stress ')"
echo "$OUT"

LOG=docs/perf-log.md
[ -f "$LOG" ] || printf '# 性能记录\n\n`scripts/perf.sh` 每跑一次追加一节。只比较同一台机器、同一个库副本上的数字。\n' > "$LOG"
{
    printf '\n## %s · %s · %s\n\n```\n' "$LABEL" "$(git rev-parse --short HEAD)" "$(date '+%Y-%m-%d %H:%M')"
    echo "$OUT" | sed 's/^stress //'
    printf '```\n'
} >> "$LOG"
