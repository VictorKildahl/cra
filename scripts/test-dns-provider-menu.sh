#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-dns-menu.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/SecureDNS.swift Sources/Cra/UI/Settings/DNSProviderMenu.swift \
  Tests/DNSProviderMenuTests.swift -o "$TEST_DIR/dns-menu-tests"
"$TEST_DIR/dns-menu-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/dns-menu-tests" "$CRA_TEST_KEEP/"
