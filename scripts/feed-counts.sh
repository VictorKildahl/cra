#!/bin/bash
# Prints the download counts of a release's update feeds (appcast*.xml), one tab-separated line each:
#   <recorded at, UTC>  <release tag>  <asset>  <download count>
#   scripts/feed-counts.sh v0.1.49
# GitHub starts an asset's count over when the asset is replaced, and scripts/promote.sh replaces the feeds on the
# latest release, so it appends these lines to scripts/feed-counts.tsv first: each feed download is one update
# check, and the daily-users estimate (docs/release.md, "Channels") adds the recorded counts back.
set -euo pipefail
TAG="${1:?usage: scripts/feed-counts.sh <release tag>}"
REPO="${CRA_REPO:-VictorKildahl/cra}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh api "repos/$REPO/releases/tags/$TAG" | python3 -c '
import json, sys
now, tag = sys.argv[1], sys.argv[2]
for asset in sorted(json.load(sys.stdin)["assets"], key=lambda a: a["name"]):
    name, count = asset["name"], asset["download_count"]
    if name.startswith("appcast") and name.endswith(".xml"):
        print(f"{now}\t{tag}\t{name}\t{count}")
' "$NOW" "$TAG"
