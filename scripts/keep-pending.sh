#!/bin/bash
# Keeps what a release that stopped while Apple was still notarizing needs to finish without a new
# build: per CPU with a submission in build/dist, the signed app (zipped), its DMG and the submission
# id, in <dir>/<arch>/. `CRA_RESUME=<dir> scripts/release.sh` picks them up; the Release workflow
# uploads <dir> when a build job fails and downloads it on the job's rerun.
#   scripts/keep-pending.sh <dir>
# Prints nothing and leaves <dir> empty when no CPU got as far as submitting.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"
mkdir -p "$OUT"
for ARCH in ${CRA_ARCHS:-arm64 x86_64}; do
  if [ "$ARCH" = "$(uname -m)" ]; then APP="build/Cra.app"; else APP="build/$ARCH/Cra.app"; fi
  [ -d "$APP" ] || continue
  SUFFIX="$(scripts/asset-suffix.sh "$APP")"
  DMG="build/dist/Cra$SUFFIX.dmg"
  [ -s "$DMG.submission" ] && [ -f "$DMG" ] || continue
  mkdir -p "$OUT/$ARCH"
  ditto -c -k --keepParent "$APP" "$OUT/$ARCH/Cra.app.zip"
  cp "$DMG" "$DMG.submission" "$OUT/$ARCH/"
  echo "Kept $ARCH: $(basename "$DMG"), submission $(cat "$DMG.submission")"
done
