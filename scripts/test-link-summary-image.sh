#!/bin/bash
# Real preview image transport through a controlled loopback proxy; no CEF, model or visible app.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-image.XXXXXX")"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
C=Packages/CraCore/Sources/CraCore
{ echo "import Foundation"; sed -n '/^public enum SiteKey {/,/^}/p' "$C/LinkRouting.swift"; } > "$TEST_DIR/SiteKey.swift"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/LinkSummary.swift" "$C/LinkSummaryCard.swift" "$TEST_DIR/SiteKey.swift" Sources/Cra/Services/Scheduler.swift \
  Tests/Support/ManualScheduler.swift Sources/Cra/Services/LinkSummaryImageFetch.swift \
  Tests/LinkSummaryImageTests.swift -o "$TEST_DIR/link-summary-image-tests"
mkfifo "$TEST_DIR/ready"
python3 Tests/Support/LinkSummaryImageServer.py > "$TEST_DIR/ready" &
SERVER_PID=$!
read -r PORT < "$TEST_DIR/ready"
"$TEST_DIR/link-summary-image-tests" "$PORT"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-image-tests" "$CRA_TEST_KEEP/"
