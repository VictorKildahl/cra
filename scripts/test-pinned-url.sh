#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-pinned-url-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  Sources/Cra/Model/SidebarModel.swift Sources/Cra/Model/LiveFolderModel.swift Sources/Cra/Model/LinkRouting.swift \
  Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/ItemTable.swift \
  Sources/Cra/Services/Persistence.swift Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/GitHubLiveClient.swift \
  Tests/PinnedURLTests.swift -o "$TEST_DIR/pinned-url-tests"
CRA_DATA_DIR="$TEST_DIR/profile" "$TEST_DIR/pinned-url-tests"
