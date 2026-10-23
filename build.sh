#!/bin/bash
# Builds "Looking Glass.app" into ./build. Pass --install to copy it to /Applications, --run to launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Looking Glass.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/LookingGlass"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LookingGlass"
cp Support/Info.plist "$APP/Contents/Info.plist"

# App icon: drawn by the app itself (see IconRenderer), converted to .icns.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --export-icon "$ICONSET/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/icon_1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Use a real signing identity if one exists (keeps camera permission across rebuilds); otherwise ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
codesign --force --deep --sign "${IDENTITY:--}" --entitlements Support/LookingGlass.entitlements "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

for arg in "$@"; do
  case "$arg" in
    --install) rm -rf "/Applications/Looking Glass.app"; cp -R "$APP" /Applications/; echo "Installed to /Applications";;
    --run) open "${INSTALLED:-$APP}";;
  esac
done
