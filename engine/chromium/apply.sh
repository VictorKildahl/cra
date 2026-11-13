#!/bin/bash
# apply.sh <chromium src>: puts Cra's engine layer into a Chromium checkout. Idempotent.
#   - copies engine/chromium/cra to <src>/cra (built into Chrome's framework as //cra:core)
#   - Chrome's hooks: chrome/browser/cra_engine_hooks.h, ChromeBrowserMainParts::Create adds Cra's startup
#     part, the framework exports CraEngineMain (framework.exports and .order), chrome_dll depends on //cra:core
#   - a stand-in Widevine signer (Cra plays DRM through WebKit, not Widevine)
# docs/chromium-engine.md says what the layer is for.
set -euo pipefail
SRC="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SRC/chrome/app/chrome_main.cc" ] || { echo "not a Chromium src: $SRC" >&2; exit 1; }

rsync -a --delete "$HERE/cra/" "$SRC/cra/"
cp "$HERE/hooks/cra_engine_hooks.h" "$SRC/chrome/browser/cra_engine_hooks.h"
# Google's Widevine signer isn't in public checkouts; an official build of Chrome's framework runs it.
if [ ! -f "$SRC/third_party/widevine/scripts/signature_generator.py" ]; then
  mkdir -p "$SRC/third_party/widevine/scripts"
  cp "$HERE/hooks/widevine_signature_generator.py" "$SRC/third_party/widevine/scripts/signature_generator.py"
fi

python3 -I - "$SRC" <<'EOF'
import sys
src = sys.argv[1]

def edit(path, old, new, done):
    p = f"{src}/{path}"
    s = open(p).read()
    if done in s:
        return
    if s.count(old) != 1:
        sys.exit(f"apply.sh: {path} doesn't have the expected text once; update the hook")
    open(p, "w").write(s.replace(old, new))
    print(f"hooked {path}")

notifier = '''  main_parts->AddParts(
      std::make_unique<ChromeBrowserMainExtraPartsThreadNotifier>(
          std::move(threads_ready_closure)));'''
edit("chrome/browser/chrome_browser_main.cc", notifier, notifier + '''
  if (cra::g_extra_parts_factory) {
    main_parts->AddParts(cra::g_extra_parts_factory());
  }''', "cra::g_extra_parts_factory")
edit("chrome/browser/chrome_browser_main.cc", '#include "chrome/browser/chrome_browser_main.h"\n',
     '#include "chrome/browser/chrome_browser_main.h"\n\n#include "chrome/browser/cra_engine_hooks.h"\n',
     '#include "chrome/browser/cra_engine_hooks.h"')
edit("chrome/app/framework.exports", "_ChromeMain\n", "_ChromeMain\n_CraEngineMain\n", "_CraEngineMain")
# framework.order wants _ChromeMain last.
edit("chrome/app/framework.order", "\n_ChromeMain\n", "\n_CraEngineMain\n_ChromeMain\n", "_CraEngineMain")

p = f"{src}/chrome/BUILD.gn"
s = open(p).read()
if '"//cra:core"' not in s:
    i = s.index('target(_dll_target_type, "chrome_dll")')
    anchor = '      "//chrome/common/profiler",\n'
    j = s.index(anchor, i)
    s = s[:j + len(anchor)] + '      "//cra:core",\n' + s[j + len(anchor):]
    open(p, "w").write(s)
    print("hooked chrome/BUILD.gn")
EOF
