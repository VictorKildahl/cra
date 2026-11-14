#!/bin/bash
# The actual iOS popup delegate callback, without launching WebKit or a simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-mobile-popup-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR/MobilePopupContractTests.swift" <<'PY'
from pathlib import Path
import sys
source = Path('iOS/Cra/Tabs/WebPage.swift').read_text()
start = source.index('    func webView(_ webView: WKWebView, createWebViewWith configuration:')
end = source.index('\n    }', start) + len('\n    }')
callback = source[start:end].strip()
tests = Path('iOS/Tests/MobilePopupContractTests.swift').read_text()
store = Path('iOS/Cra/Tabs/TabStore.swift').read_text()
store = '\n'.join(line for line in store.splitlines() if not line.startswith('import '))
Path(sys.argv[1]).write_text(tests.replace('// PRODUCTION_POPUP_CALLBACK', callback) + '\n' + store)
PY
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/Mobile/MobileTabs.swift \
  "$TEST_DIR/MobilePopupContractTests.swift" -o "$TEST_DIR/mobile-popup-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/mobile-popup-tests" "$CRA_TEST_KEEP/"
"$TEST_DIR/mobile-popup-tests"
