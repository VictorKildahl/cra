#!/bin/bash
# SiteIconLoader and the favicon cache against a site on 127.0.0.1; no CEF or AppKit windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-site-icon-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/SiteIconQueue.swift" "$C/SiteIcon.swift" "$C/FaviconKey.swift" "$C/FavoriteSelectionTint.swift" "$C/TabCustomIcon.swift" \
  Sources/Cra/Services/SiteIconLoader.swift Sources/Cra/Services/FaviconCache.swift \
  Sources/Cra/Services/Persistence.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Perf/Perf.swift "$C"/Perf/*.swift \
  Tests/SiteIconLoaderTests.swift -o "$TEST_DIR/site-icon-tests"
# Each test in a data folder of its own: they all fetch from 127.0.0.1, and the cache keeps icons on disk.
for t in $("$TEST_DIR/site-icon-tests" --list); do CRA_DATA_DIR="$TEST_DIR/$t" "$TEST_DIR/site-icon-tests" "$t"; done
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/site-icon-tests" "$CRA_TEST_KEEP/"
