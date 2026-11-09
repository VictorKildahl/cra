#!/bin/bash
# Publishes the CEF distribution built by scripts/build-cef.sh as a GitHub release
# asset, where scripts/fetch-cef.sh (and CI) download it from. The release is a
# pre-release so releases/latest keeps pointing at the newest Cra.
#   scripts/publish-cef.sh                        this Mac's CPU, CEF_RELEASE from fetch-cef.sh
#   CEF_ARCH=macosx64 scripts/publish-cef.sh      the Intel build, into the same release
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_BUILD_DIR="${CEF_BUILD_DIR:-$HOME/cef-build.noindex}"
eval "$(grep -E '^(CEF_VERSION|ARCH|CEF_RELEASE)=' scripts/fetch-cef.sh)"
ARCHIVE="$CEF_BUILD_DIR/chromium/src/cef/binary_distrib/cef_binary_${CEF_VERSION}_${ARCH}_minimal.tar.bz2"
[ -f "$ARCHIVE" ] || { echo "No build at $ARCHIVE; run scripts/build-cef.sh" >&2; exit 1; }

ASSET="$(mktemp -d)/cef_binary_${ARCH}_minimal.tar.bz2"
ln -s "$ARCHIVE" "$ASSET"
NOTES="CEF ${CEF_VERSION} for macOS, one asset per CPU (macosarm64, macosx64), built by scripts/build-cef.sh with proprietary codecs (H.264/AAC) and scripts/cef-patches. Downloaded by scripts/fetch-cef.sh; not a Cra release."
if gh release view "$CEF_RELEASE" >/dev/null 2>&1; then
  gh release upload "$CEF_RELEASE" "$ASSET" --clobber
else
  gh release create "$CEF_RELEASE" "$ASSET" --prerelease --latest=false --title "CEF ${CEF_VERSION%%+*} (codecs)" --notes "$NOTES"
fi
echo "Published $CEF_RELEASE"
