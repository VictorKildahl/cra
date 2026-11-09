#!/bin/bash
# Prints the release-asset suffix for a built Cra.app: nothing for Apple silicon
# (Cra.dmg, Cra.zip, appcast.xml), "-Intel" for Intel (Cra-Intel.dmg, Cra-Intel.zip,
# appcast-intel.xml). Asset names carry no version, so releases/latest/download links work.
#   scripts/asset-suffix.sh path/to/Cra.app
set -euo pipefail
EXE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$1/Contents/Info.plist")"
ARCHS="$(lipo -archs "$1/Contents/MacOS/$EXE")"
case "$ARCHS" in
  arm64)  echo "" ;;
  x86_64) echo "-Intel" ;;
  *) echo "Cra.app at $1 is $ARCHS; a release asset holds exactly one CPU (arm64 or x86_64)" >&2; exit 1 ;;
esac
