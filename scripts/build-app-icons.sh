#!/bin/bash
# Package the presets that the app and Dock plug-in display.
set -euo pipefail
APP="$1"
ARCH="${2:-$(uname -m)}"
IDENTITY="${3:--}"
SOURCE_DIR="$(cd "$(dirname "$0")/../resources/app-icons" && pwd)"
rsync -a --delete --exclude='*.icon' "$SOURCE_DIR/" "$APP/Contents/Resources/app-icons/"

stage="$(mktemp -d "${TMPDIR:-/tmp}/cra-icons.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Helpers"

# Older Xcode builds include the PNG presets only.
sdk="$(xcrun --sdk macosx --show-sdk-version)"
if [ "${sdk%%.*}" -ge 26 ]; then
  # IconServices draws its current icon style for a real app. It badges an app with no executable as unavailable.
  xcrun --sdk macosx clang -arch "$ARCH" -mmacosx-version-min=14.0 -x c - -o "$stage/CraIcon" <<< 'int main(void) { return 0; }'
  app_id="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"
  build="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")"
  signing=(--force --sign "$IDENTITY")
  if [ "$IDENTITY" != "-" ]; then signing+=(--options runtime --timestamp); fi

  for source in "$SOURCE_DIR"/AppIcon-*.icon; do
    name="$(basename "$source" .icon)"
    id="$(printf '%s' "${name#AppIcon-}" | tr '[:upper:]' '[:lower:]')"
    helper="$stage/Helpers/CraIcon-$id.app"
    plist="$helper/Contents/Info.plist"
    resources="$helper/Contents/Resources"
    mkdir -p "$helper/Contents/MacOS" "$resources"
    cp "$stage/CraIcon" "$helper/Contents/MacOS/CraIcon"
    echo "Compiling $name.icon..."
    xcrun --sdk macosx actool "$source" --compile "$resources" \
      --app-icon "$name" --platform macosx --target-device mac --minimum-deployment-target 14.0 \
      --output-partial-info-plist "$plist" --output-format human-readable-text --errors --warnings
    plutil -insert CFBundleIdentifier -string "$app_id.icon.$id" "$plist"
    plutil -insert CFBundleExecutable -string CraIcon "$plist"
    plutil -insert CFBundleName -string "CraIcon-$id" "$plist"
    plutil -insert CFBundlePackageType -string APPL "$plist"
    plutil -insert CFBundleVersion -string "$build" "$plist"
    plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
    plutil -insert LSBackgroundOnly -bool YES "$plist"
    [ -s "$resources/Assets.car" ] && [ -s "$resources/$name.icns" ] || {
      echo "Missing compiled icon resources for $source" >&2
      exit 1
    }
    codesign "${signing[@]}" "$helper"
  done
fi

# Only replace this script's helpers in an existing development build.
rsync -a --delete --include='/CraIcon-*.app/' --include='/CraIcon-*.app/**' --exclude='*' \
  "$stage/Helpers/" "$APP/Contents/Helpers/"
