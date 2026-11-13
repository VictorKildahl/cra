#!/bin/bash
# spike.sh <chromium out dir> <work dir>: the engine test build's run (docs/chromium-engine.md, step 1).
# Makes CraEngine.app from the built Chromium.app with engine/host as its executable, runs the checks in
# spike_checks.mm against a fresh profile folder, and prints their CRA-SPIKE lines and the exit code.
# The test window opens on CRA_TEST_SCREEN's display (part of its name). TABS (default 20) pages are open when
# the processes are measured; SPIKE_PAGE replaces the test's own page (scripts/perf's bench page, to compare).
set -uo pipefail
OUT="$1"; WORK="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$WORK/CraEngine.app"
mkdir -p "$WORK"
rm -rf "$APP"
cp -c -R "$OUT/Chromium.app" "$APP"
FW="$APP/Contents/Frameworks/Chromium Framework.framework"
clang++ -arch arm64 -mmacosx-version-min=12.0 -O2 "$ROOT/engine/host/main.mm" \
  -F "$APP/Contents/Frameworks" -framework "Chromium Framework" -o "$APP/Contents/MacOS/Chromium" || exit 1
codesign --force --sign - "$APP" >/dev/null 2>&1
PAGE="$WORK/page.html"
echo '<!doctype html><title>Cra engine test</title><h1>Cra engine test</h1>' > "$PAGE"
DATA="$WORK/profile"
mkdir -p "$DATA"
"$APP/Contents/MacOS/Chromium" --user-data-dir="$DATA" --no-first-run --no-startup-window --use-mock-keychain \
  --disable-features=DisableLoadExtensionCommandLineSwitch --enable-features=AperitifHelpers --load-extension="$ROOT/Tests/Fixtures/Extension" \
  --cra-spike --cra-spike-page="${SPIKE_PAGE:-file://$PAGE}" --cra-spike-extension="$(cat "$ROOT/Tests/Fixtures/Extension/ID")" \
  --cra-spike-screen="${CRA_TEST_SCREEN:-}" --cra-spike-tabs="${TABS:-20}" > "$WORK/stdout.log" 2> "$WORK/stderr.log" &
PID=$!
# With TABS pages open, each process's footprint (scripts/perf/procs.sh).
for _ in $(seq 120); do grep -q "CRA-SPIKE MEASURE" "$WORK/stderr.log" 2>/dev/null && break; kill -0 $PID 2>/dev/null || break; sleep 0.5; done
if grep -q "CRA-SPIKE MEASURE" "$WORK/stderr.log"; then
  FP="$ROOT/build/perf/fp"; [ -x "$FP" ] || xcrun swiftc -O "$ROOT/scripts/perf/fp.swift" -o "$FP"
  "$ROOT/scripts/perf/procs.sh" "$FP" $PID > "$WORK/procs.txt"
  R=$(awk '/--type=renderer/ {a[n++]=$4} END {print a[int(n/2)]}' "$WORK/procs.txt")
  [ -n "$R" ] && vmmap --summary "$R" > "$WORK/renderer-vmmap.txt" 2>/dev/null && vmmap "$R" > "$WORK/renderer-vmmap-full.txt" 2>/dev/null
fi
wait $PID
code=$?
grep "CRA-SPIKE" "$WORK/stderr.log"
[ -f "$WORK/procs.txt" ] && awk '{t+=$1} /renderer/{r+=$1; c++} /browser/{b=$1} /gpu/{g=$1} END {printf "memory: total %d MB, browser %d, gpu %d, renderers %d (%d)\n", t, b, g, r, c}' "$WORK/procs.txt"
echo "exit code $code"
