#!/bin/bash
# spike.sh <chromium out dir> <work dir>: the engine test build's run (docs/chromium-engine.md, step 1).
# Makes CraEngine.app from the built Chromium.app with engine/host as its executable, runs the checks in
# spike_checks.mm against a fresh profile folder, and prints their CRA-SPIKE lines and the exit code.
# The test window opens on CRA_TEST_SCREEN's display (part of its name), behind other apps' windows.
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
  --disable-features=DisableLoadExtensionCommandLineSwitch --load-extension="$ROOT/Tests/Fixtures/Extension" \
  --cra-spike --cra-spike-page="file://$PAGE" --cra-spike-extension="$(cat "$ROOT/Tests/Fixtures/Extension/ID")" \
  --cra-spike-screen="${CRA_TEST_SCREEN:-}" > "$WORK/stdout.log" 2> "$WORK/stderr.log"
code=$?
grep "CRA-SPIKE" "$WORK/stderr.log"
echo "exit code $code"
