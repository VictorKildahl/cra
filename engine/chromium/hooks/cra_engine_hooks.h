// Cra's hooks into Chrome's startup (engine/chromium in the Cra repository). //cra sets them before
// ChromeMain runs; Chrome itself never does, so nothing here changes Chrome's behaviour.
#ifndef CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
#define CHROME_BROWSER_CRA_ENGINE_HOOKS_H_

#include <memory>
#include <optional>
#include <string>

#include "base/files/file_path.h"
#include "base/functional/callback.h"

class ChromeBrowserMainExtraParts;

namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}
namespace download {
class DownloadItem;
}
class GURL;

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

// A key in a page: before the page sees it (`unhandled` false: Cra's reserved shortcuts) or after the page left
// it (true). -1 for a page that isn't Cra's, which keeps Chrome's handling; else 1 handled, 0 not. Chrome's own
// shortcuts never run for Cra's pages: its window never shows (patches/cra-keys.patch).
using KeyEventHook = int (*)(content::WebContents* contents,
                             const input::NativeWebKeyboardEvent& event,
                             bool unhandled);
inline KeyEventHook g_key_event = nullptr;

// Where a download is saved: Cra's app decides (its save panel, or its Downloads folder) instead of Chrome's
// save panel, for every download (Cra sets download.prompt_for_download). `done` gets the path, or nothing to
// cancel (patches/cra-downloads.patch).
using DownloadPathHook = void (*)(download::DownloadItem* download,
                                  const base::FilePath& suggested_path,
                                  base::OnceCallback<void(std::optional<base::FilePath>)> done);
inline DownloadPathHook g_download_path = nullptr;

// Element fullscreen in a page of Cra's (a video's fullscreen button): Cra's window shows it, Chrome's never
// does. `g_page_fullscreen` enters or leaves (false for a page that isn't Cra's); `g_page_is_fullscreen` is -1
// for a page that isn't Cra's, else 0 or 1 (patches/cra-fullscreen-status.patch).
using PageFullscreenHook = bool (*)(content::WebContents* contents, bool enter);
inline PageFullscreenHook g_page_fullscreen = nullptr;
using PageIsFullscreenHook = int (*)(const content::WebContents* contents);
inline PageIsFullscreenHook g_page_is_fullscreen = nullptr;

// The link under the pointer in a page of Cra's (empty when none), for Cra's own status line. False for a page
// that isn't Cra's.
using TargetURLHook = bool (*)(content::WebContents* contents, const GURL& url);
inline TargetURLHook g_target_url = nullptr;

}  // namespace cra

#endif  // CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
