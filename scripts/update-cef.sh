#!/bin/bash
# Moves Cra to a newer CEF: builds it with codecs, publishes it, then pins it.
#   scripts/update-cef.sh 156.0.14+g4fa4ab5+chromium-156.0.8078.48
# The version comes from the "Chromium engine update" issue that the CEF updates
# workflow opens (scripts/check-cef-update.sh). Runs for hours on this Mac; ~80 GB.
# fetch-cef.sh is only switched once the build is published, so other builds keep
# working meanwhile. The Intel build follows the arm64 one from the same checkout (about
# as long again), so the pin only moves once both are published. Afterwards: test
# build/Cra.app, commit, tag a release.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: scripts/update-cef.sh <cef_version>}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+g[0-9a-f]+\+chromium-[0-9.]+$ ]] || { echo "Not a CEF version: $NEW" >&2; exit 1; }

export CEF_VERSION="$NEW"
export CEF_RELEASE="cef-${NEW%%+*}-codecs1"
scripts/build-cef.sh
scripts/publish-cef.sh
scripts/rebuild-cef.sh x64
CEF_ARCH=macosx64 scripts/publish-cef.sh
unset CEF_VERSION CEF_RELEASE

# Pin it; a new CEF version starts again at codecs1.
sed -i '' -E "s/^CEF_VERSION=.*/CEF_VERSION=\"\${CEF_VERSION:-$NEW}\"/; s/-codecs[0-9]+\}/-codecs1}/" scripts/fetch-cef.sh
scripts/fetch-cef.sh
scripts/build.sh
echo "Cra now builds with CEF $NEW. Test build/Cra.app, then commit scripts/fetch-cef.sh and tag a release."
