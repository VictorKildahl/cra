#!/bin/bash
# Makes a release the Stable channel's (GitHub #476, docs/release.md "Channels"):
#   scripts/promote.sh 0.1.46            rewrite the feeds on the latest release, set scripts/stable-version and
#                                        commit it with scripts/feed-counts.tsv (push main afterwards)
#   scripts/promote.sh 0.1.46 --dry-run  write them to build/promote and upload nothing
# The latest GitHub release carries the feeds every Cra reads (releases/latest/download/...): appcast.xml
# (the newest release for engine builds, then Stable) and appcast-stable.xml (Stable alone), each per CPU.
# Promoting rewrites both from the two releases' own appcasts, so the signatures stay the ones the releases
# were signed with. The next release carries Stable forward from scripts/stable-version, so push the commit.
# Uploading over the feeds starts their download counts over, so their counts go to scripts/feed-counts.tsv first.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/promote.sh <version> [--dry-run]}"
VERSION="${VERSION#v}"
DRY="${2:-}"
REPO=VictorKildahl/cra

LATEST="$(gh release view -R "$REPO" --json tagName -q .tagName)"
NEWEST="${LATEST#v}"
gh release view -R "$REPO" "v$VERSION" --json tagName >/dev/null || { echo "No release v$VERSION" >&2; exit 1; }

# Stable gets only a build whose web features passed (docs/web-features.md): release.sh ran them on it and put
# web-features-arm64.txt in the release. CRA_PROMOTE_UNTESTED="<why>" promotes one without (a release from before
# the check, an emergency); say why in the commit.
if [ -z "${CRA_PROMOTE_UNTESTED:-}" ]; then
  GATE="$(mktemp -d /tmp/cra-promote-gate.XXXXXX)"
  if ! gh release download -R "$REPO" "v$VERSION" -p "web-features-arm64.txt" -D "$GATE" --clobber 2>/dev/null; then
    echo "Cra $VERSION has no web-features-arm64.txt: its web features were never run (CRA_PROMOTE_UNTESTED=\"<why>\")" >&2
    rm -rf "$GATE"; exit 1
  fi
  cat "$GATE/web-features-arm64.txt"
  grep -qx "result: passed" "$GATE/web-features-arm64.txt" ||
    { echo "Cra $VERSION failed its web features: not promoted" >&2; rm -rf "$GATE"; exit 1; }
  rm -rf "$GATE"
else
  echo "Promoting without web features: $CRA_PROMOTE_UNTESTED"
fi
if [ "$(printf '%s\n%s\n' "$VERSION" "$NEWEST" | sort -V | tail -1)" != "$NEWEST" ]; then
  echo "Cra $VERSION is newer than the latest release ($NEWEST)" >&2
  exit 1
fi

WORK="$(mktemp -d /tmp/cra-promote.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
OUT="build/promote"
rm -rf "$OUT" && mkdir -p "$OUT"
for SUFFIX in "" "-intel"; do
  mkdir -p "$WORK/newest" "$WORK/stable"
  gh release download -R "$REPO" "$LATEST" -p "appcast$SUFFIX.xml" -D "$WORK/newest" --clobber
  gh release download -R "$REPO" "v$VERSION" -p "appcast$SUFFIX.xml" -D "$WORK/stable" --clobber
  python3 scripts/appcast-feeds.py "$OUT" "$SUFFIX" "$WORK/newest/appcast$SUFFIX.xml" "$NEWEST" \
    "$WORK/stable/appcast$SUFFIX.xml" "$VERSION"
done

# Replacing a feed starts its download count over, and those counts are the update checks the daily-users
# estimate reads: keep them in scripts/feed-counts.tsv before the upload.
COUNTS="$(CRA_REPO="$REPO" scripts/feed-counts.sh "$LATEST")"
if [ "$DRY" = "--dry-run" ]; then
  printf '%s\n' "$COUNTS"
  echo "Dry run: feeds in $OUT, nothing uploaded, counts above not kept."
  exit 0
fi
printf '%s\n' "$COUNTS" >> scripts/feed-counts.tsv
gh release upload -R "$REPO" "$LATEST" --clobber "$OUT"/appcast*.xml
printf '%s\n' "$VERSION" > scripts/stable-version
# Committed here, those two files only (a shared checkout may hold other work), so the counts and the
# Stable version can't be left behind. Pushing stays yours: the next release reads stable-version from main.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git commit -q -m "Stable is Cra $VERSION" -m "scripts/promote.sh: feeds on $LATEST; their download counts before the upload are in scripts/feed-counts.tsv." \
    -- scripts/stable-version scripts/feed-counts.tsv
  echo "Stable is Cra $VERSION (feeds on $LATEST), committed as $(git rev-parse --short HEAD). Push main before the next release."
else
  echo "Stable is Cra $VERSION (feeds on $LATEST). Commit scripts/stable-version and scripts/feed-counts.tsv."
fi
