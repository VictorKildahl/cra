#!/bin/bash
# Fails when the iPhone app, or any extension in it, was linked against an iOS SDK older than the
# first one that knows every iPhone it runs on. iOS keeps an app linked on an older SDK in
# compatibility mode on a newer screen: App Store 0.1.2 (build 1478, iOS 26.5 SDK) ran on the
# iPhone Duo with a black column where the closed screen's status column is, and as a phone-sized
# window in the middle of the open screen, while every build from source (iOS 27 SDK) filled both.
# scripts/ios-testflight.sh runs it on the archive before uploading.
#
#   scripts/ios-sdk-check.sh <Cra.app>
set -euo pipefail

# The iPhone Duo came with iOS 27.1 (its simulator needs that runtime or newer).
MIN_SDK="27.1"

app="${1:?usage: scripts/ios-sdk-check.sh <Cra.app>}"
bundles=("$app")
for extension in "$app"/PlugIns/*.appex; do
  [ -d "$extension" ] && bundles+=("$extension")
done

old=()
for bundle in "${bundles[@]}"; do
  executable="$(plutil -extract CFBundleExecutable raw "$bundle/Info.plist")"
  sdk="$(vtool -show-build "$bundle/$executable" | awk '$1 == "sdk" { print $2; exit }')"
  if [ -z "$sdk" ] || [ "$(printf '%s\n%s\n' "$MIN_SDK" "$sdk" | sort -V | head -1)" != "$MIN_SDK" ]; then
    old+=("$(basename "$bundle") (iOS SDK ${sdk:-unknown})")
  fi
done

if [ ${#old[@]} -gt 0 ]; then
  echo "ios-sdk-check: linked against an iOS SDK older than $MIN_SDK: ${old[*]}" >&2
  echo "ios-sdk-check: iOS would run it in compatibility mode on the iPhone Duo; archive with Xcode 27.1 or newer" >&2
  exit 1
fi
echo "ios-sdk-check: ${#bundles[@]} binaries linked against iOS SDK $MIN_SDK or newer"
