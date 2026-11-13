#!/bin/bash
# Production bounded quote scripts on a controlled DOM surface; real CEF/WebKit remain engine gates.
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
python3 - "$TEST_DIR/QuoteEvaluation+Production.mm" <<'PYBRIDGE'
from pathlib import Path
import sys
source = Path("Sources/CraCEF/CraCEF.mm").read_text()
start = source.index("- (void)evaluateInIsolatedWorld:")
end = source.index("- (BOOL)startAgentDownload:", start)
Path(sys.argv[1]).write_text(source[start:end])
PYBRIDGE
xcrun clang++ -std=c++17 -fobjc-arc -Wno-nullability-completeness -I "$TEST_DIR" \
  -framework Foundation Tests/AskOnPageEvaluationTests.mm -o "$TEST_DIR/ask-quote-evaluation-tests"
"$TEST_DIR/ask-quote-evaluation-tests"
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/SpaceTheme.swift" "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/AskOnPageContent.swift" \
  "$TEST_DIR/Export.swift" -o "$TEST_DIR/ask-quote-export"
"$TEST_DIR/ask-quote-export" "$TEST_DIR/ask-quote-retire.js" > "$TEST_DIR/ask-quote.js"
node Tests/AskOnPageQuoteDOMTests.js "$TEST_DIR/ask-quote.js" "$TEST_DIR/ask-quote-retire.js"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-quote-evaluation-tests" "$TEST_DIR/ask-quote-export" "$TEST_DIR/ask-quote.js" "$TEST_DIR/ask-quote-retire.js" "$CRA_TEST_KEEP/"
