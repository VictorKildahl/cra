#!/bin/bash
# Actual baseline download service/history/destination with suspended inference and throwaway files.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-shared-downloads.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 ${CRA_TEST_SWIFTC_FLAGS:-} -emit-module -emit-object -parse-as-library -module-name CraCEF \
  Tests/Support/SharedDownloadsCEF.swift -emit-module-path "$TEST_DIR/CraCEF.swiftmodule" -o "$TEST_DIR/CraCEF.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" "$TEST_DIR/CraCEF.o" \
  Packages/CraCore/Sources/CraCore/TidyDownloads.swift Packages/CraCore/Sources/CraCore/DownloadList.swift \
  Packages/CraCore/Sources/CraCore/DownloadRow.swift Packages/CraCore/Sources/CraCore/DownloadLocation.swift \
  Sources/Cra/Services/TidyDownloadsService.swift Sources/Cra/Services/DownloadHistory.swift \
  Sources/Cra/Services/DownloadDestinations.swift Tests/Support/SharedDownloadsSupport.swift \
  Tests/SharedDownloadReplacementTests.swift -o "$TEST_DIR/shared-download-tests"
"$TEST_DIR/shared-download-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/shared-download-tests" "$CRA_TEST_KEEP/"
