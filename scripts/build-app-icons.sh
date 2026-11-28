#!/bin/bash
# Install Segments as the primary icon and each native alternate as a signed app for IconServices.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$1"
arch="$2"
identity="${3:--}"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

scripts/compile-app-icon.sh "$stage/primary"
bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
version=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")
signing=(--force --sign "$identity")
if [[ $identity != - ]]; then signing+=(--options runtime --timestamp); fi
# IconServices badges bundles without an executable as unavailable.
xcrun --sdk macosx clang -arch "$arch" -mmacosx-version-min=14.0 -x c - -o "$stage/CraIcon" <<< 'int main(void) { return 0; }'

for source in resources/app-icons/AppIcon-*.icon; do
  name=$(basename "$source" .icon)
  label=${name#AppIcon-}
  id=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
  helper="$stage/Helpers/CraIcon-$id.app"
  contents="$helper/Contents"
  mkdir -p "$contents/MacOS"
  cp "$stage/CraIcon" "$contents/MacOS/CraIcon"
  scripts/compile-app-icon.sh "$contents/Resources" "$source"
  plist="$contents/Info.plist"
  mv "$contents/Resources/partial.plist" "$plist"
  plutil -insert CFBundleIdentifier -string "$bundle_id.icon.$id" "$plist"
  plutil -insert CFBundleExecutable -string CraIcon "$plist"
  plutil -insert CFBundleName -string "$label" "$plist"
  plutil -insert CFBundlePackageType -string APPL "$plist"
  plutil -insert CFBundleVersion -string "$version" "$plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
  plutil -insert LSBackgroundOnly -bool YES "$plist"
  codesign "${signing[@]}" "$helper"
done

mkdir -p "$app/Contents/Helpers" "$app/Contents/Resources/app-icons"
rsync -a --delete --include='/CraIcon-*.app/' --include='/CraIcon-*.app/**' --exclude='*' "$stage/Helpers/" "$app/Contents/Helpers/"
cp "$stage/primary/Assets.car" "$stage/primary/AppIcon.icns" "$app/Contents/Resources/"
cp "$stage/primary/segments-glass.png" "$app/Contents/Resources/app-icons/"
# CI archives the primary icon separately from the app.
if [ -n "${4:-}" ]; then
  mkdir -p "$4"
  rsync -a "$stage/primary/" "$4/"
fi
