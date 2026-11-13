#!/bin/bash
# Production card/request ownership and FoundationModels adapter; --real-model explicitly runs synthetic on-device samples.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-service.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
# Compile these exact command paths against the narrow window/browser/clipboard seams.
# No copied routing logic or production test hook is needed to exercise MWC's integration.
python3 - "$TEST_DIR/SelectionWindow+Production.swift" <<'PYCODE'
from pathlib import Path
import sys
source = Path("Sources/Cra/UI/Windows/MainWindowController.swift").read_text()
def between(start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]
callback = between("        overlay.onFindQueryChange = { [weak self] query in", "        browsers.windowID = session.id")
methods = [between("    func useSelectionForFind() {", "    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection"),
           between("    func showFindBar() {", "    func hideFindBar() {"),
           between("    private func find(_ q: String, forward: Bool) {", "    /// Ask on Page or the plain find bar")]
Path(sys.argv[1]).write_text("import AppKit\n\n@MainActor extension SelectionWindow {\n"
    + "    func wireProductionQueryCallback() {\n" + callback + "    }\n" + "\n".join(methods) + "}\n")
PYCODE
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/SpaceTheme.swift" "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/ObserveChanges.swift" \
  Sources/Cra/Services/AskOnPageService.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/UI/AskOnPageCard.swift Sources/Cra/UI/Overlays.swift Sources/Cra/UI/AppKitControls.swift "$C/FirstClick.swift" \
  Tests/Support/ManualScheduler.swift Tests/AskOnPageSupport/BrowserServices.swift Tests/AskOnPageSupport/AppServices.swift Tests/AskOnPageSupport/CardServices.swift \
  "$TEST_DIR/SelectionWindow+Production.swift" Tests/AskOnPageSelectionTests.swift \
  Tests/AskOnPageControllerTests.swift Tests/AskOnPageServiceTests.swift -o "$TEST_DIR/ask-service-tests"
"$TEST_DIR/ask-service-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-service-tests" "$CRA_TEST_KEEP/"
