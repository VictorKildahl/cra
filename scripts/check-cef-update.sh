#!/bin/bash
# Compares the CEF pinned in scripts/fetch-cef.sh with the newest stable CEF for
# macOS arm64 and, when Cra is behind, opens (or updates) one "Chromium engine
# update" issue saying how to build it. Run daily by .github/workflows/cef-updates.yml.
#   scripts/check-cef-update.sh --dry-run   print instead of touching issues
#   scripts/check-cef-update.sh --check     exit 1 when Cra is behind (release.sh and the
#                                            release-tag hook: a release ships the newest CEF)
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(grep -E '^CEF_VERSION=' scripts/fetch-cef.sh)"
LATEST="$(curl -fsSL https://cef-builds.spotifycdn.com/index.json |
  jq -r '[.macosarm64.versions[] | select(.channel == "stable")][0].cef_version')"
[ -n "$LATEST" ] && [ "$LATEST" != null ] || { echo "Could not read the CEF index" >&2; exit 1; }

major() { cut -d. -f1 <<<"$1"; }
chromium() { sed 's/.*chromium-//' <<<"$1"; }
cef() { sed 's/+.*//' <<<"$1"; }
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
echo "Pinned: $CEF_VERSION"
echo "Latest: $LATEST"
# Chromium decides first: security fixes land there. Cra can pin CEF's branch head on a newer
# Chromium patch than Spotify's build (156.0.27 on .96), and a later CEF on the older patch is not
# an update: building it would take Chromium back (#355). A newer CEF only counts on the same
# Chromium. Check its CEF-only commits by hand with
# gh api repos/chromiumembedded/cef/compare/<ours>...<theirs>.
if newer "$(chromium "$LATEST")" "$(chromium "$CEF_VERSION")"; then
  :
elif [ "$(chromium "$LATEST")" = "$(chromium "$CEF_VERSION")" ] && newer "$(cef "$LATEST")" "$(cef "$CEF_VERSION")"; then
  :
else
  if newer "$(cef "$LATEST")" "$(cef "$CEF_VERSION")"; then
    echo "CEF $(cef "$LATEST") is on an older Chromium ($(chromium "$LATEST")) than Cra's ($(chromium "$CEF_VERSION")), so it doesn't count."
  fi
  echo "Cra is up to date."
  exit 0
fi
if [ "${1:-}" = --check ]; then
  echo "Cra is behind the newest stable CEF: build it with scripts/update-cef.sh $LATEST" >&2
  exit 1
fi

if [ "$(major "$LATEST")" = "$(major "$CEF_VERSION")" ]; then
  KIND="a security/bug-fix update on the same Chromium version, so the build reuses the existing checkout (typically 1-2 hours)"
else
  KIND="a new Chromium version ($(major "$CEF_VERSION") → $(major "$LATEST")), so the build fetches a new checkout and compiles everything (3-4 hours, ~80 GB free)"
fi
TITLE="Chromium engine update available"
BODY="$(cat <<EOF
Cra ships CEF \`$CEF_VERSION\` (Chromium $(chromium "$CEF_VERSION")). The newest stable CEF is **\`$LATEST\`** (Chromium $(chromium "$LATEST")).

This is $KIND. Chromium only ships security fixes for its newest version, so Cra should move soon.

On the Mac that builds the engine:

\`\`\`sh
scripts/update-cef.sh $LATEST
\`\`\`

It builds CEF with H.264/AAC and \`scripts/cef-patches\`, publishes it as the \`cef-${LATEST%%+*}-codecs1\` pre-release and pins it in \`scripts/fetch-cef.sh\`. Then test \`build/Cra.app\`, commit and tag a release. If a patch in \`scripts/cef-patches\` no longer applies, the build stops and says which one.

_Checked daily by the CEF updates workflow; this issue is updated when an even newer CEF appears._
EOF
)"

if [ "${1:-}" = --dry-run ]; then
  echo "--- would open or update issue: $TITLE"
  echo "$BODY"
  exit 0
fi
EXISTING="$(gh issue list --state open --search "\"$TITLE\" in:title" --json number,body -q '.[0]')"
if [ -z "$EXISTING" ]; then
  gh issue create --title "$TITLE" --body "$BODY" --assignee "${GITHUB_REPOSITORY_OWNER:-@me}"
elif ! grep -qF "$LATEST" <<<"$(jq -r .body <<<"$EXISTING")"; then
  gh issue edit "$(jq -r .number <<<"$EXISTING")" --body "$BODY"
  gh issue comment "$(jq -r .number <<<"$EXISTING")" --body "Newer CEF available: \`$LATEST\`. The steps above are updated."
else
  echo "Issue already up to date."
fi
