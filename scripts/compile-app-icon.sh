#!/bin/bash
# Xcode 27 compiles the layered icon and its legacy .icns from the same Icon Composer document.
# scripts/compile-app-icon.sh <out dir> [document.icon]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: scripts/compile-app-icon.sh <out dir> [document.icon]}"
ICON="${2:-resources/AppIcon.icon}"
ICON="$(cd "$ICON" && pwd)"
NAME="$(basename "$ICON" .icon)"
sdk=$(xcrun --sdk macosx --show-sdk-version)
if (( ${sdk%%.*} < 27 )); then
  echo "Compiling $NAME requires Xcode 27 (selected macOS SDK: $sdk)." >&2
  exit 1
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
ICTOOL="${DEVELOPER_DIR:-$(xcode-select -p)}/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ICTOOL" ] || { echo "compile-app-icon.sh: no ictool at $ICTOOL" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cra-app-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Both tools resolve relative paths against their own server's folder, not this one, and report a file they can't
# open on stdout with a zero exit: the outputs are checked instead.
mkdir -p "$TMP/actool"
xcrun --sdk macosx actool "$ICON" --compile "$TMP/actool" --app-icon "$NAME" \
  --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$OUT/partial.plist" --output-format human-readable-text --errors --warnings > /dev/null
[ -s "$TMP/actool/Assets.car" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$OUT/partial.plist" 2>/dev/null)" = "$NAME" ] ||
  { echo "compile-app-icon.sh: actool made no $NAME catalog from $ICON" >&2; exit 1; }
cp "$TMP/actool/Assets.car" "$OUT/Assets.car"

"$ICTOOL" "$ICON" --export-image --output-file "$TMP/full.png" --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1 > /dev/null
[ -s "$TMP/full.png" ] || { echo "compile-app-icon.sh: ictool rendered nothing from $ICON" >&2; exit 1; }

# Build a 1024 px legacy icon on Apple's grid. actool's .icns stops at 256 px.
sips -z 824 824 "$TMP/full.png" --out "$TMP/tile.png" > /dev/null
sips -p 1024 1024 "$TMP/tile.png" --out "$TMP/grid.png" > /dev/null
mkdir -p "$TMP/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$TMP/grid.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/grid.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT/$NAME.icns"
if [ "$NAME" = AppIcon ]; then
  sips -z 512 512 "$TMP/grid.png" --out "$OUT/segments-glass.png" > /dev/null
fi
