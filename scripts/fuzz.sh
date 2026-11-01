#!/bin/bash
# Mutated copies of the importer fixtures through their parsers, under AddressSanitizer
# (Tests/FuzzTests.swift). CRA_FUZZ_ITERATIONS (default 20000) and CRA_FUZZ_SEED; a crash
# leaves its input in build/fuzz/crash-input.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-fuzz.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p build/fuzz
xcrun swiftc -swift-version 5 -parse-as-library -sanitize=address -g \
  Packages/CraCore/Sources/CraCore/*.swift Sources/Cra/Services/Import/*.swift \
  Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift Sources/Cra/Services/Persistence.swift \
  Sources/Cra/Services/GitHubLiveClient.swift Sources/Cra/Services/FaviconCache.swift \
  Sources/Cra/Services/SafeStorage.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Tests/FuzzTests.swift -o "$TEST_DIR/fuzz"
CRA_FUZZ_OUT="$PWD/build/fuzz" "$TEST_DIR/fuzz"
