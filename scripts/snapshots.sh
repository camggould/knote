#!/bin/bash
# Render the UI to PNGs offscreen for visual review / snapshot testing.
# Usage: scripts/snapshots.sh [output-dir]   (default: ./snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-snapshots}"
swift build >/dev/null
BIN="$(swift build --show-bin-path)/knote"
"$BIN" --snapshot "$OUT"
echo "✓ snapshots in $OUT/"
ls -1 "$OUT"
