#!/bin/bash
# Build knote and assemble a menu-bar .app bundle (no Xcode project needed).
# Usage: scripts/make_app.sh [--release]  →  produces build/Knote.app
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"

# Version stamped into the bundle (CI passes the git tag, e.g. "0.1.0").
VERSION="${KNOTE_VERSION:-0.1.0}"

echo "› swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/knote"
APP="build/Knote.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/knote"

# App icon (generate with scripts/make_icon.py if missing).
if [[ -f Icon/AppIcon.icns ]]; then
    cp Icon/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
else
    echo "  (no Icon/AppIcon.icns — run scripts/make_icon.py to add an icon)"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>knote</string>
    <key>CFBundleDisplayName</key>     <string>knote</string>
    <key>CFBundleIdentifier</key>      <string>com.knote.app</string>
    <key>CFBundleExecutable</key>      <string>knote</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>__VERSION__</string>
    <key>CFBundleVersion</key>         <string>__VERSION__</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- Accessory app: no Dock icon, runs in the background. -->
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>knote — local, private notes launcher</string>
</dict>
</plist>
PLIST

# Stamp the version into the plist.
sed -i '' "s/__VERSION__/$VERSION/g" "$CONTENTS/Info.plist"

# Ad-hoc sign so the login-item API and hardened launch behave locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built $APP (v$VERSION)"
