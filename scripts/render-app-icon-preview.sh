#!/bin/bash
# Renders resources/AppIcon.icon (the Icon Composer icon macOS 26 shows in the Dock) into
# resources/app-icons/segments-glass.png, Settings ▸ Icon's Segments tile on macOS 26: 512 px, the tile 412 px and
# centred on Apple's grid like the picker's other tiles (GitHub #865). Run it after changing AppIcon.icon.
# Needs Xcode 26 (Icon Composer's ictool).
#   scripts/render-app-icon-preview.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ICTOOL" ] || { echo "render-app-icon-preview.sh: no ictool at $ICTOOL (Xcode 26's Icon Composer)" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$ICTOOL" "$PWD/resources/AppIcon.icon" --export-image --output-file "$TMP/full.png" --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1 >/dev/null
sips -z 412 412 "$TMP/full.png" --out "$TMP/tile.png" >/dev/null
sips -p 512 512 "$TMP/tile.png" --out resources/app-icons/segments-glass.png >/dev/null
echo "resources/app-icons/segments-glass.png"
