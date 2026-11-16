#!/bin/bash
# Compares the Chrome version the engine is built from (scripts/fetch-engine.sh) with Chrome's newest stable for
# macOS (Google's version history API). Chromium fixes security bugs only in its newest version, so a release ships
# the newest stable engine.
#   scripts/check-engine-update.sh           print both
#   scripts/check-engine-update.sh --check   exit 1 when the engine is behind (release.sh)
#   scripts/check-engine-update.sh --issue   when behind, open (or update) one "Chromium engine update" issue saying
#                                             how to build it (daily, .github/workflows/engine-updates.yml)
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
if ! newer "$LATEST" "$ENGINE_VERSION"; then
  echo "The engine is up to date."
  exit 0
fi
echo "The engine is behind Chrome stable"
[ "${1:-}" = --check ] && exit 1
[ "${1:-}" = --issue ] || exit 0

major() { cut -d. -f1 <<<"$1"; }
if [ "$(major "$LATEST")" = "$(major "$ENGINE_VERSION")" ]; then
  KIND="a security and bug-fix update of the same Chrome version, so the build reuses the checkout"
else
  KIND="a new Chrome version ($(major "$ENGINE_VERSION") → $(major "$LATEST")), so Cra's patches may need rebasing and the build compiles everything"
fi
TITLE="Chromium engine update available"
BODY="Cra's engine is built from Chrome \`$ENGINE_VERSION\`. Chrome's newest stable for macOS is **\`$LATEST\`**.

This is $KIND. Chromium ships security fixes only for its newest version, so Cra should move soon.

On the Mac that builds the engine (docs/chromium-engine.md):

\`\`\`sh
CHROMIUM_TAG=$LATEST scripts/build-chromium.sh all
CHROMIUM_TAG=$LATEST CRA_ARCH=x64 scripts/build-chromium.sh all
scripts/publish-engine.sh && ENGINE_CPU=x64 scripts/publish-engine.sh
\`\`\`

Then set \`ENGINE_VERSION=$LATEST\` in \`scripts/fetch-engine.sh\`, run the scenarios on \`build/Cra.app\`, commit and tag a release.

_Checked daily by the engine updates workflow; this issue is updated when an even newer Chrome appears._"

EXISTING="$(gh issue list --state open --search "\"$TITLE\" in:title" --json number,body -q '.[0]')"
if [ -z "$EXISTING" ]; then
  gh issue create --title "$TITLE" --body "$BODY" --assignee "${GITHUB_REPOSITORY_OWNER:-@me}"
elif ! grep -qF "$LATEST" <<<"$(jq -r .body <<<"$EXISTING")"; then
  gh issue edit "$(jq -r .number <<<"$EXISTING")" --body "$BODY"
  gh issue comment "$(jq -r .number <<<"$EXISTING")" --body "Newer Chrome stable: \`$LATEST\`. The steps above are updated."
else
  echo "Issue already up to date."
fi
