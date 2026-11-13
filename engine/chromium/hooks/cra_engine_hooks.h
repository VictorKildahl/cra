// Cra's hooks into Chrome's startup (engine/chromium in the Cra repository). //cra sets them before
// ChromeMain runs; Chrome itself never does, so nothing here changes Chrome's behaviour.
#ifndef CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
#define CHROME_BROWSER_CRA_ENGINE_HOOKS_H_

#include <memory>

class ChromeBrowserMainExtraParts;

namespace cra {

// Cra's part of the browser process's startup, added after Chrome's own parts.
using ExtraPartsFactory = std::unique_ptr<ChromeBrowserMainExtraParts> (*)();
inline ExtraPartsFactory g_extra_parts_factory = nullptr;

// Cra's app made NSApp, its delegate and its main menu before ChromeMain: Chrome's AppController
// (NSApp's delegate in Chrome) and Chrome's main menu are never made (chrome_browser_main_mac.mm).
inline bool g_embedder_owns_app = false;

}  // namespace cra

#endif  // CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
