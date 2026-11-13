#!/bin/bash
# Compares the Chrome version the engine is built from (scripts/fetch-engine.sh) with Chrome's newest stable for
# macOS (Google's version history API). Chromium fixes security bugs only in its newest version, so a release ships
# the newest stable engine.
#   scripts/check-engine-update.sh           print both
#   scripts/check-engine-update.sh --check   exit 1 when the engine is behind (release.sh)
# To update: CHROMIUM_TAG=<newest> scripts/build-chromium.sh, for both CPUs, then scripts/publish-engine.sh and
# a new ENGINE_VERSION in fetch-engine.sh (docs/chromium-engine.md).
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(grep -E '^ENGINE_VERSION=' scripts/fetch-engine.sh)"
LATEST="$(curl -fsSL "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions?pageSize=1" |
  jq -r '.versions[0].version')"
[ -n "$LATEST" ] && [ "$LATEST" != null ] || { echo "Could not read Chrome's version history" >&2; exit 1; }
echo "Engine: $ENGINE_VERSION"
echo "Chrome: $LATEST"
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
if newer "$LATEST" "$ENGINE_VERSION"; then
  echo "The engine is behind Chrome stable"
  [ "${1:-}" = --check ] && exit 1
fi
exit 0
