#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-app-icons.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/Cra.app"
mkdir -p "$APP/Contents/Resources"
sed -e 's/__VERSION__/1.0/g' -e 's/__BUILD__/1/g' resources/Info.plist > "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "dk.kildahl.cra.icon-tests.$(uuidgen)" "$APP/Contents/Info.plist"
scripts/build-app-icons.sh "$APP" "$(uname -m)"
for helper in "$APP"/Contents/Helpers/CraIcon-*.app; do
  codesign --verify --strict "$helper"
  lipo "$helper/Contents/MacOS/CraIcon" -verify_arch "$(uname -m)"
done
mkdir -p "$APP/Contents/MacOS"
cp "$APP/Contents/Helpers/CraIcon-original.app/Contents/MacOS/CraIcon" "$APP/Contents/MacOS/Cra"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/CraAppIcons/AppIconResources.swift Tests/AppIconResourcesTests.swift -o "$TEST_DIR/app-icon-tests"
(cd "$TEST_DIR" && ./app-icon-tests "$APP")
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/app-icon-tests" "$CRA_TEST_KEEP/"
