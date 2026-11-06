#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-mcp-transport.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library $CRA_TEST_SWIFTC_FLAGS \
  Packages/CraCore/Sources/CraCore/MCPInputPlan.swift \
  Packages/CraCore/Sources/CraCore/MCPProtocol.swift \
  Sources/Cra/Services/MCPListener.swift Sources/Cra/Services/MCPConnection.swift Tests/MCPTransportTests.swift -o "$TEST_DIR/mcp-tests"
"$TEST_DIR/mcp-tests"
python3 Tests/mcp_bridge_test.py "$TEST_DIR/mcp-tests"
[ -z "$CRA_TEST_KEEP" ] || cp "$TEST_DIR/mcp-tests" "$CRA_TEST_KEEP/"
