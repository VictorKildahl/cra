#!/bin/bash
# Dev loop: debug build into build/CraDev.app, launch it, and rebuild + relaunch on
# every save under Sources/ or resources/.
#   scripts/dev.sh           watch and relaunch (Ctrl-C quits the app too)
#   scripts/dev.sh --once    build and launch once, logs in this terminal
#   CRA_DATA_DIR=<dir> scripts/dev.sh    use another profile (default Application Support/CraDev)
# CraDev is its own app (executable name, bundle id, profile), so it runs next to the
# installed Cra, `killall Cra` elsewhere leaves it alone, and it never claims cra:// or
# http links. CEF is copied and signed when its pinned source changes; ordinary rebuilds swap the Cra binaries,
# in a separate SwiftPM scratch dir so parallel `scripts/build.sh` runs don't collide.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
NAME=CraDev
APP="$ROOT/build/$NAME.app"
SCRATCH="$ROOT/.build/dev"
STAMP="$SCRATCH/.dev-stamp"
export CRA_DATA_DIR="${CRA_DATA_DIR:-$HOME/Library/Application Support/CraDev}"
PB=/usr/libexec/PlistBuddy
PID=""

# "<name suffix>|<plist suffix>", as in scripts/build.sh.
HELPERS=("|" " (Alerts)|.alerts" " (GPU)|.gpu" " (Plugin)|.plugin" " (Renderer)|.renderer")

bootstrap() {
  echo "Creating $APP with the current CEF and Sparkle builds..."
  rm -rf "$APP" || return 1
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" || return 1
  sed -e "s/__VERSION__/0.0.0-dev/" -e "s/__BUILD__/0/" resources/Info.plist > "$APP/Contents/Info.plist"
  $PB -c "Set :CFBundleExecutable $NAME" -c "Set :CFBundleIdentifier dk.kildahl.cra.dev" \
      -c "Set :CFBundleName $NAME" -c "Set :CFBundleDisplayName $NAME" \
      -c "Delete :CFBundleURLTypes" -c "Delete :CFBundleDocumentTypes" \
      -c "Delete :UTExportedTypeDeclarations" "$APP/Contents/Info.plist"
  $PB -c "Delete :SUFeedURL" "$APP/Contents/Info.plist"
  echo -n "APPL????" > "$APP/Contents/PkgInfo"
  [ -f resources/AppIcon.icns ] && cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  local fw="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
  cp -R "$ROOT/vendor/cef/Release/Chromium Embedded Framework.framework" "$APP/Contents/Frameworks/" || return 1
  find "$fw/Libraries" -name '*.dylib' -exec codesign --force --sign - {} \; 2>/dev/null || return 1
  codesign --force --sign - "$fw" || return 1
  ditto "$ROOT/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework" || return 1
  local sparkle="$APP/Contents/Frameworks/Sparkle.framework"
  rm -rf "$sparkle/Versions/B/XPCServices" "$sparkle/XPCServices"
  codesign --force --sign - "$sparkle/Versions/B/Autoupdate" || return 1
  codesign --force --sign - "$sparkle/Versions/B/Updater.app" || return 1
  codesign --force --sign - "$sparkle" || return 1
  for entry in "${HELPERS[@]}"; do
    local ns="${entry%%|*}" ps="${entry#*|}"
    local helper="$APP/Contents/Frameworks/$NAME Helper$ns.app"
    mkdir -p "$helper/Contents/MacOS"
    sed -e "s/__NAME_SUFFIX__/$ns/g" -e "s/__PLIST_SUFFIX__/$ps/g" -e "s/__VERSION__/0.0.0-dev/" -e "s/__BUILD__/0/" \
        -e "s/Cra Helper/$NAME Helper/g" -e "s/dk\.kildahl\.cra\.helper/dk.kildahl.cra.dev.helper/" \
        resources/Helper-Info.plist > "$helper/Contents/Info.plist"
    echo -n "APPL????" > "$helper/Contents/PkgInfo"
  done
  cp "$ROOT/vendor/cef/.cra-source" "$APP/Contents/Resources/cef-source" || return 1
  cp "$ROOT/vendor/sparkle/VERSION" "$APP/Contents/Resources/sparkle-version" || return 1
}

# A separately launched CraDev (or a second watch process) must be quit before its
# bundle is changed. Match helper names too: they may briefly outlive the main app.
dev_app_running() {
  ps -axo comm= | awk -F/ -v name="$NAME" \
    '$NF == name || index($NF, name " Helper") == 1 { found = 1 } END { exit !found }'
}

# Compile while the current app is usable, then stop it before changing its bundle.
build() {
  mkdir -p "$SCRATCH"
  touch "$STAMP"
  scripts/fetch-cef.sh >/dev/null || return 1
  scripts/fetch-sparkle.sh >/dev/null || return 1
  swift build -c debug --scratch-path "$SCRATCH" || return 1
  local bin
  bin="$(swift build -c debug --scratch-path "$SCRATCH" --show-bin-path)" || return 1
  stop
  for _ in $(seq 20); do dev_app_running || break; sleep 0.1; done
  if dev_app_running; then
    echo "Quit the separately running CraDev before rebuilding its app bundle." >&2
    return 1
  fi
  if [ ! -d "$APP/Contents/Frameworks/$NAME Helper.app" ] || \
     [ ! -f "$APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" ] || \
     [ ! -d "$APP/Contents/Frameworks/Sparkle.framework" ] || \
     ! cmp -s "$ROOT/vendor/cef/.cra-source" "$APP/Contents/Resources/cef-source" || \
     ! cmp -s "$ROOT/vendor/sparkle/VERSION" "$APP/Contents/Resources/sparkle-version"; then
    bootstrap || return 1
  fi
  for entry in "${HELPERS[@]}"; do
    local ns="${entry%%|*}"
    local helper="$APP/Contents/Frameworks/$NAME Helper$ns.app"
    if ! cmp -s "$bin/CraHelper" "$helper/Contents/MacOS/$NAME Helper$ns"; then
      cp "$bin/CraHelper" "$helper/Contents/MacOS/$NAME Helper$ns" || return 1
      codesign --force --sign - --entitlements resources/CraHelper.entitlements "$helper" || return 1
    fi
  done
  cp "$bin/Cra" "$APP/Contents/MacOS/$NAME" || return 1
  for d in web brand blocklist browsers app-icons; do
    if [ -d "resources/$d" ]; then
      rsync -a --delete "resources/$d/" "$APP/Contents/Resources/$d/" || return 1
    fi
  done
  codesign --force --sign - --entitlements resources/Cra.entitlements "$APP"
}

stop() {
  [ -n "$PID" ] || return 0
  if kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
    for _ in $(seq 50); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
    kill -KILL "$PID" 2>/dev/null || true
  fi
  wait "$PID" 2>/dev/null || true
  PID=""
}

launch() {
  "$APP/Contents/MacOS/$NAME" &
  PID=$!
  echo "▶ $NAME running (pid $PID, profile $CRA_DATA_DIR)"
}

changed() {
  [ scripts/fetch-cef.sh -nt "$STAMP" ] || [ scripts/fetch-sparkle.sh -nt "$STAMP" ] || \
  [ -n "$(find Sources resources Package.swift -newer "$STAMP" -type f \
          \( -name '*.swift' -o -name '*.m' -o -name '*.mm' -o -name '*.h' -o -path 'resources/*' \) \
          -print -quit 2>/dev/null)" ]
}

trap 'stop; exit 0' INT TERM
trap stop EXIT

if dev_app_running; then
  echo "Quit the separately running CraDev before rebuilding its app bundle." >&2
  exit 1
fi
if build; then
  launch
else
  [ "${1:-}" = "--once" ] && exit 1
  echo "✗ Build failed; fix it and save to retry."
fi
if [ "${1:-}" = "--once" ]; then wait "$PID"; exit 0; fi

echo "Watching Sources/ and resources/ (Ctrl-C to quit)"
while true; do
  sleep 0.4
  changed || continue
  sleep 0.2  # let editors finish multi-file saves
  echo "↻ Change detected, rebuilding..."
  start=$(date +%s)
  if build; then
    launch
    echo "✓ Relaunched in $(( $(date +%s) - start ))s"
  else
    echo "✗ Rebuild failed; fix the error and save to retry."
  fi
done
