// CraEngineMain: Cra's entry into Chrome's framework. Sets Cra's startup hooks, then runs Chrome's
// own ChromeMain. Exported by chrome/app/framework.exports (engine/chromium/apply.sh).

#include <memory>
#include <string>
#include <vector>

#include "base/command_line.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "cra/bridge.h"
#include "cra/spike_checks.h"

extern "C" int ChromeMain(int argc, const char** argv);

namespace {

// Cra's part of the browser process's start-up: the app's ready blocks once Chrome is up, and the engine
// test's checks when it runs (--cra-spike).
class CraParts : public ChromeBrowserMainExtraParts {
 public:
  void PostBrowserStart() override {
    cra::RunReadyBlocks();
    spike_->PostBrowserStart();
  }

 private:
  std::unique_ptr<ChromeBrowserMainExtraParts> spike_ = cra::MakeSpikeParts();
};

std::unique_ptr<ChromeBrowserMainExtraParts> MakeCraParts() {
  return std::make_unique<CraParts>();
}

// Features Cra always runs with, added to the browser's --enable-features (Chromium reads only one).
// AperitifHelpers: the helper apps that link the framework at launch, so its 12 MB __DATA_CONST stays
// clean in every page, GPU and utility process (docs/chromium-engine.md); off by default in 156.
constexpr char kCraFeatures[] = "AperitifHelpers";

}  // namespace

extern "C" __attribute__((visibility("default"))) int CraEngineMain(int argc, const char** argv) {
  cra::g_extra_parts_factory = &MakeCraParts;
  // Live for the whole process (Chromium keeps argv); never freed.
  auto& args = *new std::vector<std::string>(argv, argv + argc);
  const std::string prefix = "--enable-features=";
  bool merged = false;
  for (std::string& arg : args) {
    if (arg.rfind(prefix, 0) == 0) {
      arg += std::string(arg.size() > prefix.size() ? "," : "") + kCraFeatures;
      merged = true;
    }
  }
  if (!merged) {
    args.push_back(prefix + kCraFeatures);
  }
  auto& pointers = *new std::vector<const char*>();
  for (const std::string& arg : args) {
    pointers.push_back(arg.c_str());
  }
  // The placeholder +[CraApplication load] made goes; Chrome reads this one.
  if (base::CommandLine::InitializedForCurrentProcess()) {
    base::CommandLine::Reset();
  }
  return ChromeMain(static_cast<int>(pointers.size()), pointers.data());
}
