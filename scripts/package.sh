#!/bin/bash
# Packages build/Cra.app into build/dist/: a zip, a DMG with the drag-to-install
# window (resources/dmg), and SHA-256 checksums. Signs the DMG when CRA_SIGN_IDENTITY is set.
#   scripts/package.sh [path/to/Cra.app]
# An Apple silicon app becomes Cra.zip and Cra.dmg, an Intel one Cra-Intel.zip and
# Cra-Intel.dmg. Each run replaces only its own files, so both can sit in build/dist.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Cra.app}"
[ -d "$APP" ] || { echo "No app at $APP. Run scripts/build.sh first." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
IDENTITY="${CRA_SIGN_IDENTITY:--}"
DIST="build/dist"
SUFFIX="$(scripts/asset-suffix.sh "$APP")"
ZIP="$DIST/Cra$SUFFIX.zip"
DMG="$DIST/Cra$SUFFIX.dmg"
mkdir -p "$DIST"
rm -f "$ZIP" "$DMG"

# Zip: ditto keeps resource forks and symlinks, which codesign requires.
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG: dmgbuild writes the Finder layout (background, icon positions, hidden
# chrome) into .DS_Store directly, so no Finder scripting and it works on CI.
# Layout in resources/dmg/settings.py.
VENV="build/dmgbuild-venv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.7
fi
"$VENV/bin/dmgbuild" -s resources/dmg/settings.py -D app="$APP" "Cra" "$DMG"
if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

(cd "$DIST" && shasum -a 256 Cra*.zip Cra*.dmg > SHA256SUMS.txt)
echo "Packaged:"
ls -la "$DIST"
