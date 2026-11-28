#!/bin/bash
# Builds Cra's icon from resources/AppIcon.icon (Gilad's Icon Composer icon, PR #690) into <out>:
#   Assets.car + partial.plist  the catalog macOS 26 and later draw in the Dark, Clear and Tinted icon styles
#                               (CFBundleIconName AppIcon; a plain .icns stays as drawn, GitHub #739)
#   AppIcon.icns                the icon on macOS 14 and 15, the Alerts helper's and the DMG's: Icon Composer's
#                               Default rendering at 1024 px on Apple's grid (actool's own .icns stops at 256 px)
#   segments-glass.png          Settings ▸ Icon's Segments tile on macOS 26, 512 px with the tile 412 (GitHub #865)
#   scripts/compile-app-icon.sh <out dir>
# The icon uses macOS 27 features (refraction, the specular highlight inside each segment) that only Xcode 27's
# actool and ictool read; Xcode 26's can't open the file. On an older Xcode this builds from a copy without them and
# says so, for day-to-day builds. A release (CRA_RELEASE=1) refuses: it ships the icon as designed, as
# .github/workflows/release.yml does on Xcode 27.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: scripts/compile-app-icon.sh <out dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
ICON="$PWD/resources/AppIcon.icon"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ICTOOL" ] || { echo "compile-app-icon.sh: no ictool at $ICTOOL (Xcode's Icon Composer)" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cra-app-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

XCODE="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $2 }')"
if [ "${XCODE%%.*}" -lt 27 ] 2>/dev/null; then
  if [ "${CRA_RELEASE:-}" = 1 ]; then
    echo "compile-app-icon.sh: a release needs Xcode 27 (this is Xcode $XCODE): it renders the icon's macOS 27 features" >&2
    exit 1
  fi
  echo "compile-app-icon.sh: Xcode $XCODE can't read the icon's macOS 27 features; this build's icon goes without them" >&2
  cp -R "$ICON" "$TMP/AppIcon.icon"
  python3 - "$TMP/AppIcon.icon/icon.json" <<'EOF'
import json, sys
path = sys.argv[1]
icon = json.load(open(path))
icon.pop("features", None)
for group in icon.get("groups", []):
    if isinstance(group.get("specular"), str):
        group["specular"] = True
json.dump(icon, open(path, "w"), indent=2)
EOF
  ICON="$TMP/AppIcon.icon"
fi

# Both tools resolve relative paths against their own server's folder, not this one, and report a file they can't
# open on stdout with a zero exit: the outputs are checked instead.
mkdir -p "$TMP/actool"
xcrun --sdk macosx actool "$ICON" --compile "$TMP/actool" --app-icon AppIcon \
  --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$OUT/partial.plist" --output-format human-readable-text --errors --warnings > /dev/null
[ -s "$TMP/actool/Assets.car" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$OUT/partial.plist" 2>/dev/null)" = AppIcon ] ||
  { echo "compile-app-icon.sh: actool made no AppIcon catalog from $ICON" >&2; exit 1; }
cp "$TMP/actool/Assets.car" "$OUT/Assets.car"

"$ICTOOL" "$ICON" --export-image --output-file "$TMP/full.png" --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1 > /dev/null
[ -s "$TMP/full.png" ] || { echo "compile-app-icon.sh: ictool rendered nothing from $ICON" >&2; exit 1; }

# Apple's grid: the tile 824 of 1024 px, centred (412 of 512 for the picker's tiles).
sips -z 824 824 "$TMP/full.png" --out "$TMP/tile.png" > /dev/null
sips -p 1024 1024 "$TMP/tile.png" --out "$TMP/grid.png" > /dev/null
mkdir -p "$TMP/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$TMP/grid.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/grid.png" --out "$TMP/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT/AppIcon.icns"
sips -z 512 512 "$TMP/grid.png" --out "$OUT/segments-glass.png" > /dev/null
