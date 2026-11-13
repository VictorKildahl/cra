// CraEngineMain: Cra's entry into Chrome's framework. Sets Cra's startup hooks, then runs Chrome's
// own ChromeMain. Exported by chrome/app/framework.exports (engine/chromium/apply.sh).

#include <memory>

#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "cra/spike_checks.h"

extern "C" int ChromeMain(int argc, const char** argv);

namespace {

std::unique_ptr<ChromeBrowserMainExtraParts> MakeCraParts() {
  return cra::MakeSpikeParts();
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int CraEngineMain(int argc, const char** argv) {
  cra::g_extra_parts_factory = &MakeCraParts;
  return ChromeMain(argc, argv);
}
