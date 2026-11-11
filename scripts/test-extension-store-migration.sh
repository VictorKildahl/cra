#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-extension-migration.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/ExtensionStoreSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Packages/CraCore/Sources/CraCore/ExtensionProfiles.swift \
  Packages/CraCore/Sources/CraCore/WebStoreInstalls.swift \
  Packages/CraCore/Sources/CraCore/UnpackedCopies.swift \
  Packages/CraCore/Sources/CraCore/PinnedExtensions.swift \
  Packages/CraCore/Sources/CraCore/ExtensionActionState.swift \
  Packages/CraCore/Sources/CraCore/ExtensionBadge.swift \
  Packages/CraCore/Sources/CraCore/ExtensionIcons.swift \
  Packages/CraCore/Sources/CraCore/ExtensionProxyControl.swift \
  Sources/Cra/Services/Import/ExtensionImporter.swift Sources/Cra/Services/ExtensionStore.swift \
  Tests/ExtensionStoreSupport/AppServices.swift Tests/ExtensionStoreMigrationTests.swift \
  -o "$TEST_DIR/extension-migration-tests"
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/extension-migration-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/extension-migration-tests" "$CRA_TEST_KEEP/"
