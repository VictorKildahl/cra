#!/bin/bash
# The iPhone app (iOS/Cra.xcodeproj) in the iOS Simulator, without opening Xcode or the
# Simulator window: the device boots headless and is looked at through screenshots.
#
#   scripts/ios.sh build              # build into build/ios
#   scripts/ios.sh run [args…]        # build, install, launch; args go to the app
#                                     # (-CraDataDir fresh, -CraOpenURL https://example.com)
#   scripts/ios.sh shot <file.png>    # screenshot of the simulator
#   scripts/ios.sh test [only…]       # the UI tests (iOS/CraUITests); `only` as CraUITests/Class/test.
#                                     # Their screenshots land in build/ios/test-screens
#   scripts/ios.sh open               # show the Simulator window
#
# CRA_IOS_SIM names the simulator (default "Cra iPhone 17"); it is created on the newest
# installed iOS runtime when missing. Xcode needs the iOS platform that matches its SDK:
# `xcodebuild -downloadPlatform iOS` fetches it.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${CRA_IOS_SIM:-Cra iPhone 17}"
DERIVED="build/ios"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Cra.app"
BUNDLE_ID="dk.kildahl.cra"

device() {
  local udid
  udid="$(xcrun simctl list devices available | awk -v name="$SIM_NAME" -F '[()]' 'index($0, name " (") { print $2; exit }')"
  if [ -z "$udid" ]; then
    local runtime type
    runtime="$(xcrun simctl list runtimes | awk '/^iOS/ { id = $NF } END { print id }')"
    type="$(xcrun simctl list devicetypes | awk -F '[()]' '/^iPhone 17 \(/ { print $2; exit }')"
    [ -n "$type" ] || type="$(xcrun simctl list devicetypes | awk -F '[()]' '/^iPhone/ { id = $2 } END { print id }')"
    if [[ "$SIM_NAME" == *iPad* ]]; then
      type="$(xcrun simctl list devicetypes | awk -F '[()]' '/^iPad Pro 11-inch/ { print $(NF-1); exit }')"
    fi
    udid="$(xcrun simctl create "$SIM_NAME" "$type" "$runtime")"
  fi
  echo "$udid"
}

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

build() {
  local udid="$1"
  xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" build 2>&1 |
    grep -E "error|warning: [^M]|BUILD (SUCCEEDED|FAILED)" || true
  [ -d "$APP" ] || { echo "build failed" >&2; exit 1; }
}

command="${1:-run}"
shift || true
UDID="$(device)"

case "$command" in
  build)
    build "$UDID"
    ;;
  run)
    build "$UDID"
    boot "$UDID"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
    ;;
  shot)
    boot "$UDID"
    xcrun simctl io "$UDID" screenshot "${1:?usage: scripts/ios.sh shot <file.png>}" >/dev/null 2>&1
    echo "$1"
    ;;
  test)
    boot "$UDID"
    only=()
    for name in "$@"; do only+=("-only-testing:$name"); done
    rm -rf "$DERIVED/test.xcresult" "$DERIVED/test-screens"
    # PopupTests posts forms to a local fixture server (a data: page can't take a POST). It
    # takes a free port, so parallel runs don't collide; the simulator shares the Mac's loopback.
    # CertificateTests reach it over HTTPS with a certificate made for this run, which nothing trusts.
    server_log="$(mktemp "${TMPDIR:-/tmp}/cra-popup-server.XXXXXX")"
    tls_dir="$(mktemp -d "${TMPDIR:-/tmp}/cra-untrusted-tls.XXXXXX")"
    trap 'rm -rf "$tls_dir"' EXIT
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=cra.localhost" \
      -addext "subjectAltName=DNS:cra.localhost,IP:127.0.0.1" -keyout "$tls_dir/key.pem" -out "$tls_dir/cert.pem" >/dev/null 2>&1
    python3 -I iOS/Tests/popup_server.py --port 0 --tls-port 0 \
      --tls-cert "$tls_dir/cert.pem" --tls-key "$tls_dir/key.pem" > "$server_log" 2>&1 &
    server=$!
    trap 'kill "$server" 2>/dev/null || true; rm -f "$server_log"; rm -rf "$tls_dir"' EXIT
    base=""
    for _ in $(seq 100); do
      base="$(sed -n 's#^Popup fixtures: \(http://[^/]*\)/source$#\1#p' "$server_log")"
      [ -z "$base" ] || break
      kill -0 "$server" 2>/dev/null || break
      sleep 0.1
    done
    [ -n "$base" ] || { cat "$server_log" >&2; echo "popup fixture server didn't start" >&2; exit 1; }
    # xcodebuild hands TEST_RUNNER_-prefixed variables to the UI test runner, without the prefix.
    export TEST_RUNNER_CRA_POPUP_TEST_BASE_URL="$base"
    TEST_RUNNER_CRA_UNTRUSTED_TEST_URL="$(sed -n 's#^Untrusted fixtures: \(https://.*\)$#\1#p' "$server_log")"
    export TEST_RUNNER_CRA_UNTRUSTED_TEST_URL
    # One simulator: parallel testing clones it per worker, which loads the Mac and has left a
    # run waiting for a runner that never launched.
    xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Debug \
      -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" \
      -resultBundlePath "$DERIVED/test.xcresult" -parallel-testing-enabled NO \
      ${only[@]+"${only[@]}"} test 2>&1 |
      grep -E "error|Test Case .*(passed|failed)|Executed|TEST (SUCCEEDED|FAILED)|BUILD FAILED" || true
    # The screenshots the tests attached, as build/ios/test-screens/<name>.png.
    if [ -d "$DERIVED/test.xcresult" ]; then
      xcrun xcresulttool export attachments --path "$DERIVED/test.xcresult" --output-path "$DERIVED/test-screens" >/dev/null 2>&1 || true
      python3 -I - "$DERIVED/test-screens" <<'PY' || true
import json, os, sys
folder = sys.argv[1]
manifest = os.path.join(folder, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            source = os.path.join(folder, item.get("exportedFileName", ""))
            # "name_0_<uuid>.png" as attached by XCTest: the screenshots keep the name the test
            # gave them; XCTest's own attachments (recordings, hierarchy dumps) keep theirs.
            if name.endswith(".png") and "_0_" in name and os.path.exists(source):
                os.replace(source, os.path.join(folder, name.split("_0_")[0] + ".png"))
PY
    fi
    ;;
  open)
    boot "$UDID"
    open -a Simulator --args -CurrentDeviceUDID "$UDID"
    ;;
  *)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
