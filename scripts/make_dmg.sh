#!/bin/bash
# Build a drag-to-Applications disk image from build/Knote.app.
# Usage: scripts/make_dmg.sh   (honors $KNOTE_VERSION; builds the app if needed)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${KNOTE_VERSION:-0.1.0}"
APP="build/Knote.app"
[[ -d "$APP" ]] || ./scripts/make_app.sh

DMG="build/knote-${VERSION}-macos-arm64.dmg"
STAGE="$(mktemp -d)"

# Lay out the mounted window: the app next to an Applications alias so the user
# just drags across.
cp -R "$APP" "$STAGE/Knote.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "knote" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov "$DMG" >/dev/null

rm -rf "$STAGE"
echo "✓ Built $DMG"
