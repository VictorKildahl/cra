#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[ "${SDK_VERSION%%.*}" -ge 26 ] || exit 0
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-app-icons.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/Cra.app"
mkdir -p "$APP/Contents/Resources"
sed -e 's/__VERSION__/1.0/g' -e 's/__BUILD__/1/g' resources/Info.plist > "$APP/Contents/Info.plist"
cp resources/AppIcon.icns "$APP/Contents/Resources/"
scripts/build-app-icons.sh "$APP"
for helper in "$APP"/Contents/Helpers/CraIcon-*.app; do
  codesign --verify --strict "$helper"
  lipo "$helper/Contents/MacOS/CraIcon" -verify_arch "$(uname -m)"
done
mkdir -p "$APP/Contents/MacOS"
cp "$APP/Contents/Helpers/CraIcon-arc.app/Contents/MacOS/CraIcon" "$APP/Contents/MacOS/Cra"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/CraAppIcons/AppIconResources.swift Tests/AppIconResourcesTests.swift -o "$TEST_DIR/app-icon-tests"
# An installed copy must load every preset even when it cannot access Documents or the checkout.
(cd "$TEST_DIR" && /usr/bin/sandbox-exec -D "DOCUMENTS=$HOME/Documents" -D "SOURCE=$OLDPWD/resources/app-icons" \
  -p '(version 1)(allow default)(deny file-read* file-write* (subpath (param "DOCUMENTS")) (subpath (param "SOURCE")))' \
  ./app-icon-tests "$APP")
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/app-icon-tests" "$CRA_TEST_KEEP/"
