#!/bin/bash
# Picture in Picture overlay under trackpad events: the real overlay window and view over a stand-in for Chromium's window (transparent, click-through), events routed by AppKit, no CEF (#534, #573).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-pip-overlay.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/PictureInPictureSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Sources/Cra/UI/PictureInPicture/PictureInPictureChrome.swift Sources/Cra/UI/PictureInPicture/PictureInPictureControls.swift \
  Sources/Cra/UI/PictureInPicture/ChromiumPictureInPictureSeal.swift Sources/Cra/Services/TestGesture.swift \
  Packages/CraCore/Sources/CraCore/PictureInPicture*.swift \
  Tests/PictureInPictureSupport/AppServices.swift Tests/PictureInPictureOverlayTests.swift \
  -o "$TEST_DIR/pip-overlay-tests"
CRA_DATA_DIR="$TEST_DIR" "$TEST_DIR/pip-overlay-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/pip-overlay-tests" "$CRA_TEST_KEEP/"
