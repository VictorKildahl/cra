#!/bin/bash
# Decisions pulled out of the window controllers (extension clicks, DevTools toggle, feature flags).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-policy-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/Windows/ExtensionLaunch.swift Sources/Cra/Services/DevToolsToggle.swift Sources/Cra/App/FeatureFlags.swift \
  Tests/PolicyTests.swift -o "$TEST_DIR/policy-tests"
"$TEST_DIR/policy-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/policy-tests" "$CRA_TEST_KEEP/"
