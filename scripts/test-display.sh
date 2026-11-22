#!/bin/bash
# test-display.sh: a virtual 1728x1117 pt Retina display (a 16" MacBook Pro, the Macs the scenarios were set on) ("Cra Test Display") below the main one, for scenarios, kept
# by a background vdisplay process until it is killed (or the CI job ends). Then run scenarios on it with
#   CRA_TEST_SCREEN="Cra Test Display" scripts/scenario.sh …
# GitHub's macOS runners have one small 1x screen: a scenario's 1200x800 window didn't fit (the page came out
# 862x657 at 1x), so the geometry the scenarios check and their 2x snapshots failed there, though Cra was right.
# Prints vdisplay's "ready <id> <origin> <size>"; exits 1 when macOS won't make the display. Its pid is in
# build/vdisplay.pid, so whoever started it can end it without touching another checkout's.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
clang -fobjc-arc -framework Foundation -framework CoreGraphics -Wno-objc-property-no-attribute \
  scripts/test-display/vdisplay.m -o build/vdisplay || exit 1
nohup build/vdisplay "$@" > build/vdisplay.log 2>&1 &
echo $! > build/vdisplay.pid
for _ in $(seq 1 60); do
  if grep -q '^ready' build/vdisplay.log 2>/dev/null; then
    grep '^ready' build/vdisplay.log
    exit 0
  fi
  if ! kill -0 $! 2>/dev/null; then
    cat build/vdisplay.log >&2
    exit 1
  fi
  sleep 0.5
done
echo "test-display: no display after 30 s" >&2
cat build/vdisplay.log >&2
exit 1
