#!/bin/bash
# Compiles resources/AppIcon.icon (Icon Composer, Segments) into <out>/Assets.car with <out>/partial.plist naming it
# (CFBundleIconName AppIcon). macOS 26 draws an app's icon in the Dark, Clear and Tinted icon styles only from this
# catalog; resources/AppIcon.icns stays the icon for macOS 14 and 15 (GitHub #739). Needs Xcode 26's actool.
#   scripts/compile-app-icon.sh <out dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: scripts/compile-app-icon.sh <out dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# actool resolves relative paths against its own server's folder, not this one.
xcrun --sdk macosx actool "$PWD/resources/AppIcon.icon" --compile "$OUT" --app-icon AppIcon \
  --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$OUT/partial.plist" --output-format human-readable-text --errors --warnings
[ -s "$OUT/Assets.car" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$OUT/partial.plist" 2>/dev/null)" = AppIcon ] ||
  { echo "compile-app-icon.sh: actool made no AppIcon catalog from resources/AppIcon.icon" >&2; exit 1; }
