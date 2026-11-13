#!/bin/bash
# apply.sh <chromium src>: puts Cra's engine layer into a Chromium checkout. Idempotent.
#   - copies engine/chromium/cra to <src>/cra (built into Chrome's framework as //cra:core)
#   - Chrome's hooks: chrome/browser/cra_engine_hooks.h, ChromeBrowserMainParts::Create adds Cra's startup
#     part, ChromeBrowserMainPartsMac leaves Cra's NSApp delegate and menu alone, the framework exports CraEngineMain and the bridge's classes (framework.exports and .order), chrome_dll depends on //cra:core
#   - a stand-in Widevine signer (Cra plays DRM through WebKit, not Widevine)
# docs/chromium-engine.md says what the layer is for.
set -euo pipefail
SRC="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SRC/chrome/app/chrome_main.cc" ] || { echo "not a Chromium src: $SRC" >&2; exit 1; }

rsync -a --delete "$HERE/cra/" "$SRC/cra/"
# The bridge implements the app's header (Sources/CraCEF/include/CraCEF.h).
cp "$HERE/../../Sources/CraCEF/include/CraCEF.h" "$SRC/cra/CraCEF.h"
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
mac = "chrome/browser/chrome_browser_main_mac.mm"
edit(mac, '#include "chrome/browser/chrome_browser_main_mac.h"\n',
     '#include "chrome/browser/chrome_browser_main_mac.h"\n\n#include "chrome/browser/cra_engine_hooks.h"\n',
     '#include "chrome/browser/cra_engine_hooks.h"')
edit(mac, '''  // Create the app delegate by requesting the shared AppController.
  CHECK_EQ(nil, NSApp.delegate);''', '''  // Cra's app keeps its own delegate and main menu.
  if (cra::g_embedder_owns_app) {
    return content::RESULT_CODE_NORMAL_EXIT;
  }

  // Create the app delegate by requesting the shared AppController.
  CHECK_EQ(nil, NSApp.delegate);''', "cra::g_embedder_owns_app) {\n    return")
edit(mac, '''void ChromeBrowserMainPartsMac::DidEndMainMessageLoop() {
  [AppController.sharedController didEndMainMessageLoop];''', '''void ChromeBrowserMainPartsMac::DidEndMainMessageLoop() {
  if (cra::g_embedder_owns_app) {
    return;
  }
  [AppController.sharedController didEndMainMessageLoop];''', "if (cra::g_embedder_owns_app) {\n    return;\n  }\n  [AppController")
edit("chrome/app/framework.exports", "_ChromeMain\n", "_ChromeMain\n_CraEngineMain\n", "_CraEngineMain")
# framework.order wants _ChromeMain last among the functions.
edit("chrome/app/framework.order", "\n_ChromeMain\n", "\n_CraEngineMain\n_ChromeMain\n", "_CraEngineMain")
# The bridge's Objective-C classes (CraCEF.h), which Cra's app links against: data, after every function.
classes = ["CraApplication", "CraBrowser", "CraCEFRuntime", "CraDownloadInfo", "CraSSLStatus"]
objc = "".join(f"_OBJC_CLASS_$_{c}\n_OBJC_METACLASS_$_{c}\n" for c in classes)
edit("chrome/app/framework.exports", "_CraEngineMain\n", "_CraEngineMain\n" + objc, "_OBJC_CLASS_$_CraBrowser")
edit("chrome/app/framework.order", "\n_ChromeMain\n", "\n_ChromeMain\n" + objc, "_OBJC_CLASS_$_CraBrowser")

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
