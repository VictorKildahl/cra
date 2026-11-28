#!/bin/bash
# SwiftUI pickers use PNG previews. iOS builds the actual app icons from the .icon documents.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build/app-icon-previews}"
mkdir -p "$out"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
ictool="$developer_dir/../Applications/Icon Composer.app/Contents/Executables/ictool"
for source in resources/AppIcon.icon resources/app-icons/AppIcon-*.icon; do
  name="$(basename "$source" .icon)"
  "$ictool" "$PWD/$source" --export-image --platform iOS --rendition Default \
    --width 512 --height 512 --scale 1 --output-file "$out/$name-Preview.png"
  test -s "$out/$name-Preview.png"
done
