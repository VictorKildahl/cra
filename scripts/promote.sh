#!/bin/bash
# Makes a release the Stable channel's (GitHub #476, docs/release.md "Channels"):
#   scripts/promote.sh 0.1.46            rewrite the feeds on the latest release and set scripts/stable-version
#   scripts/promote.sh 0.1.46 --dry-run  write them to build/promote and upload nothing
# The latest GitHub release carries the feeds every Cra reads (releases/latest/download/...): appcast.xml
# (the newest release for engine builds, then Stable) and appcast-stable.xml (Stable alone), each per CPU.
# Promoting rewrites both from the two releases' own appcasts, so the signatures stay the ones the releases
# were signed with. Commit scripts/stable-version afterwards: the next release carries Stable forward from it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/promote.sh <version> [--dry-run]}"
VERSION="${VERSION#v}"
DRY="${2:-}"
REPO=VictorKildahl/cra

LATEST="$(gh release view -R "$REPO" --json tagName -q .tagName)"
NEWEST="${LATEST#v}"
gh release view -R "$REPO" "v$VERSION" --json tagName >/dev/null || { echo "No release v$VERSION" >&2; exit 1; }
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

if [ "$DRY" = "--dry-run" ]; then
  echo "Dry run: feeds in $OUT, nothing uploaded."
  exit 0
fi
gh release upload -R "$REPO" "$LATEST" --clobber "$OUT"/appcast*.xml
printf '%s\n' "$VERSION" > scripts/stable-version
echo "Stable is Cra $VERSION (feeds on $LATEST). Commit scripts/stable-version."
