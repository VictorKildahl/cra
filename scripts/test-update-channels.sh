#!/bin/bash
# Stable and New update channels (GitHub #476, docs/release.md "Channels"): scripts/appcast-feeds.py writes a
# release's feeds from Tests/Fixtures/Appcast (0.1.43's signed item as Stable, a stand-in 0.1.46 as the newest),
# a local server serves them, and the vendored Sparkle decides, for a stand-in Cra at each build, what it offers.
# Nothing is downloaded and the real Cra's settings are never touched (the stand-ins have their own bundle id).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIR="$(mktemp -d /tmp/cra-channels.XXXXXX)"
DOMAIN=dk.kildahl.cra.feedcheck
PORT=$((20000 + RANDOM % 20000))
SERVER=""
cleanup() {
  if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null || true; fi
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$DIR"
}
trap cleanup EXIT

xcrun swiftc -swift-version 5 Tests/UpdateFeedCheck.swift -F vendor/sparkle -framework Sparkle \
  -Xlinker -rpath -Xlinker "$ROOT/vendor/sparkle" -o "$DIR/feedcheck" 2>&1 | grep -v warning || true
mkdir -p "$DIR/feed"
python3 scripts/appcast-feeds.py "$DIR/feed" "" Tests/Fixtures/Appcast/newest.xml 0.1.46 Tests/Fixtures/Appcast/stable.xml 0.1.43 >/dev/null
(cd "$DIR/feed" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER=$!
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$PORT/appcast.xml" >/dev/null 2>&1 && break; sleep 0.1; done

FAILED=0
# expect <version> <build> <feed> <expected> <why>
expect() {
  local app="$DIR/stub-$1-$3.app"
  mkdir -p "$app/Contents"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$DOMAIN</string>
<key>CFBundleName</key><string>Cra</string>
<key>CFBundleShortVersionString</key><string>$1</string>
<key>CFBundleVersion</key><string>$2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>SUFeedURL</key><string>http://127.0.0.1:$PORT/$3</string>
<key>SUPublicEDKey</key><string>$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' resources/Info.plist)</string>
<key>SUEnableAutomaticChecks</key><false/>
</dict></plist>
PLIST
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  local got
  got="$("$DIR/feedcheck" "$app")"
  if [ "$got" = "$4" ]; then
    echo "ok: $5"
  else
    echo "FAILED: $5: expected '$4', got '$got'"
    FAILED=1
  fi
}

expect 0.1.42 202611121000 appcast.xml "FOUND 0.1.43 202611131845" "a Cra on CEF updates to Stable, not to the engine"
expect 0.1.43 202611131845 appcast.xml "NONE" "Cra 0.1.43 (Stable) stays where it is"
expect 0.1.44 202611161309 appcast.xml "FOUND 0.1.46 202611180000" "Cra 0.1.44, the first on the engine, takes the newest"
expect 0.1.45 202611161908 appcast.xml "FOUND 0.1.46 202611180000" "Cra 0.1.45 (no channel switch) takes the newest"
expect 0.1.46 202611180000 appcast.xml "NONE" "the newest Cra on New has nothing newer"
expect 0.1.46 202611180000 appcast-stable.xml "NONE" "a Mac switched to Stable is never taken back to an older version"
expect 0.1.40 202611111200 appcast-stable.xml "FOUND 0.1.43 202611131845" "the Stable feed offers Stable"
exit $FAILED
