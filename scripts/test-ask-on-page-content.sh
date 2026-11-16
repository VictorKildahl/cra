#!/bin/bash
# Current-document extraction in WebKit's real DOM, using the production bounded isolated script.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-content.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/SpaceTheme.swift" "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/AskOnPageContent.swift" \
  Tests/AskOnPageContentTests.swift -o "$TEST_DIR/ask-content-tests"
python3 - "$TEST_DIR/ask-content-tests" <<'PYHTTP'
import http.server, subprocess, sys, threading
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    origin = "http://127.0.0.1:" + str(server.server_port)
    result = subprocess.run([sys.argv[1], origin + "/Tests/Fixtures/AskOnPage/article.html"])
finally:
    server.shutdown()
    server.server_close()
sys.exit(result.returncode)
PYHTTP
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-content-tests" "$CRA_TEST_KEEP/"
