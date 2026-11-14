#!/bin/bash
# Actual store/settings/model notification boundaries, real per-window service and controlled browser/provider.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-lifecycle.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR/ProductionMaxSwitch.swift" <<'PYMAX'
from pathlib import Path
import sys
source = Path("Sources/Cra/UI/Settings/MaxPane.swift").read_text()
assignments = [line.strip() for line in source.splitlines() if line.strip().startswith("store.settings.") and line.strip().endswith(" = on")]
assert len(assignments) == 6
Path(sys.argv[1]).write_text("@MainActor func applyProductionMaxSwitch(_ store: SidebarStore, _ on: Bool) {\n" + "\n".join(assignments) + "\n}\n")
PYMAX
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift \
  Sources/Cra/Services/Persistence.swift Tests/Support/LegacyLiveFolderResults.swift Sources/Cra/Services/FaviconCache.swift \
  Sources/Cra/Services/SafeStorage.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/Services/TidyTabsService.swift Sources/Cra/Services/AskOnPageService.swift \
  Tests/Support/ManualScheduler.swift Tests/AskOnPageSupport/BrowserServices.swift \
  Tests/AskOnPageSupport/RealStoreServices.swift "$TEST_DIR/ProductionMaxSwitch.swift" Tests/AskOnPageLifecycleTests.swift -o "$TEST_DIR/ask-lifecycle-tests"
"$TEST_DIR/ask-lifecycle-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-lifecycle-tests" "$CRA_TEST_KEEP/"
