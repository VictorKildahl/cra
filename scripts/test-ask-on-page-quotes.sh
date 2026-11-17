#!/bin/bash
# Production bounded quote scripts on a controlled DOM surface, and each bridge's isolated-world evaluation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-quotes.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/Export.swift" <<'SWIFT'
import Foundation
@main enum Export {
    static func main() {
        let lease = UUID()
        print(AskOnPageQuoteDOM.lookup("fixture", url: "https://example.test/article", lease: lease))
        try! AskOnPageQuoteDOM.retire(lease).write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
    }
}
SWIFT
# The isolated-world evaluation of each bridge, verbatim: the engine's (what ships) and CEF's.
for bridge in engine/chromium/cra/bridge.mm Sources/CraCEF/CraCEF.mm; do
  mkdir -p "$TEST_DIR/$(dirname "$bridge")"
  python3 - "$bridge" "$TEST_DIR/$(dirname "$bridge")/QuoteEvaluation+Production.mm" <<'PYBRIDGE'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index("- (void)evaluateInIsolatedWorld:")
end = min(source.index(marker, start) for marker in ("- (BOOL)startAgentDownload:", "- (CraSSLStatus*)sslStatus") if marker in source[start:])
Path(sys.argv[2]).write_text(source[start:end])
PYBRIDGE
  xcrun clang++ -std=c++17 -fobjc-arc -Wno-nullability-completeness -I "$TEST_DIR/$(dirname "$bridge")" \
    -framework Foundation Tests/AskOnPageEvaluationTests.mm -o "$TEST_DIR/ask-quote-evaluation-tests"
  printf '%s: ' "$bridge"
  "$TEST_DIR/ask-quote-evaluation-tests"
done
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/SpaceTheme.swift" "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/AskOnPageContent.swift" \
  "$TEST_DIR/Export.swift" -o "$TEST_DIR/ask-quote-export"
"$TEST_DIR/ask-quote-export" "$TEST_DIR/ask-quote-retire.js" > "$TEST_DIR/ask-quote.js"
node Tests/AskOnPageQuoteDOMTests.js "$TEST_DIR/ask-quote.js" "$TEST_DIR/ask-quote-retire.js"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-quote-evaluation-tests" "$TEST_DIR/ask-quote-export" "$CRA_TEST_KEEP/"
