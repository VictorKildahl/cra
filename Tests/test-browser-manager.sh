#!/bin/bash
# Compile the real manager against a deterministic bridge; no Chromium or profile I/O.
set -euo pipefail
cd "$(dirname "$0")/.."
MANAGER_SOURCE="${1:-Sources/Cra/Services/BrowserManager.swift}"
TEST_DIR="$(mktemp -d /tmp/cra-lifecycle-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/BrowserManagerSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Packages/CraCore/Sources/CraCore/FaviconKey.swift Packages/CraCore/Sources/CraCore/FavoriteSelectionTint.swift Sources/Cra/Services/FaviconCache.swift \
  "$MANAGER_SOURCE" Sources/Cra/Services/BrowserManager+AskOnPage.swift Packages/CraCore/Sources/CraCore/SpaceTheme.swift Packages/CraCore/Sources/CraCore/AskOnPage.swift Packages/CraCore/Sources/CraCore/AskOnPagePrompt.swift Packages/CraCore/Sources/CraCore/AskOnPageContent.swift Sources/Cra/Services/NowPlaying.swift Sources/Cra/Services/PageScript.swift Sources/Cra/Services/Scheduler.swift Sources/Cra/Services/DevToolsToggle.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Services/PageProbe.swift Sources/Cra/Services/Persistence.swift \
  Sources/Cra/Perf/Perf.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Packages/CraCore/Sources/CraCore/ExtensionPageRetry.swift Packages/CraCore/Sources/CraCore/PermissionPrompt.swift Packages/CraCore/Sources/CraCore/PermissionAsk.swift Sources/Cra/Services/CaptureAccess.swift Packages/CraCore/Sources/CraCore/TabSleepPolicy.swift Packages/CraCore/Sources/CraCore/MemoryReclaim.swift Packages/CraCore/Sources/CraCore/SparePage.swift Sources/Cra/Services/SparePages.swift Packages/CraCore/Sources/CraCore/ProtectedMedia.swift Packages/CraCore/Sources/CraCore/PageHistory.swift Sources/Cra/Services/PageHistoryStore.swift Sources/Cra/Services/WebKit/PageEngines.swift Tests/Support/ManualScheduler.swift Tests/BrowserManagerSupport/AppServices.swift \
  Packages/CraCore/Sources/CraCore/DialogActions.swift Packages/CraCore/Sources/CraCore/Boost.swift Packages/CraCore/Sources/CraCore/PictureInPictureLayout.swift Packages/CraCore/Sources/CraCore/PictureInPictureThrow.swift Packages/CraCore/Sources/CraCore/LinkSplitClick.swift Packages/CraCore/Sources/CraCore/LittleWindowTrigger.swift Packages/CraCore/Sources/CraCore/KeyChord.swift Packages/CraCore/Sources/CraCore/PageTranslation.swift Packages/CraCore/Sources/CraCore/BlockedPopups.swift Sources/Cra/Services/BrowserManager+BlockedPopups.swift Packages/CraCore/Sources/CraCore/DevToolsPlaceholder.swift Sources/Cra/Services/BrowserManager+Translation.swift Tests/BrowserManagerLifecycleTests.swift -o "$TEST_DIR/lifecycle-tests"
# A data folder of its own: PageEngines keeps protected-media.json there, not in the real Cra's.
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/lifecycle-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/lifecycle-tests" "$CRA_TEST_KEEP/"
