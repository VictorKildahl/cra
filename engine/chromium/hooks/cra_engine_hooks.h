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

}  // namespace cra

#endif  // CHROME_BROWSER_CRA_ENGINE_HOOKS_H_
