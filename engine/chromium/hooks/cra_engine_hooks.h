// Cra's hooks into Chrome's startup (engine/chromium in the Cra repository). //cra sets them before
// ChromeMain runs; Chrome itself never does, so nothing here changes Chrome's behaviour.
#ifndef CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
#define CHROME_BROWSER_CRA_ENGINE_HOOKS_H_

#include <memory>
#include <string>

class ChromeBrowserMainExtraParts;

namespace content {
class WebContents;
}

namespace cra {

// Cra's part of the browser process's startup, added after Chrome's own parts.
using ExtraPartsFactory = std::unique_ptr<ChromeBrowserMainExtraParts> (*)();
inline ExtraPartsFactory g_extra_parts_factory = nullptr;

// Cra's app made NSApp, its delegate and its main menu before ChromeMain: Chrome's AppController
// (NSApp's delegate in Chrome) and Chrome's main menu are never made (chrome_browser_main_mac.mm).
inline bool g_embedder_owns_app = false;

// A page asked to come to the front: an extension (chrome.tabs.update with active: true, by_page false) or the
// page itself (window.focus(), clients.focus() after a notification click). Cra selects its tab; Chrome's
// window never shows (patches/page-activate.patch, patches/extension-tab-activate.patch).
using PageActivationHook = void (*)(content::WebContents* contents, bool by_page);
inline PageActivationHook g_page_activation = nullptr;

// A page's translate state changed (`state_json`: CraTranslateState plus the step), for Cra's own translate UI
// (Arc's). Returns false when the page isn't one of Cra's, which then keeps Chrome's bubble
// (patches/translate-ui.patch).
using TranslateStateHook = bool (*)(content::WebContents* contents, const std::string& state_json);
inline TranslateStateHook g_translate_state = nullptr;

}  // namespace cra

#endif  // CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
