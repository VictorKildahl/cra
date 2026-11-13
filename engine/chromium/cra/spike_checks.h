// The engine test build's checks (docs/chromium-engine.md, step 1). With --cra-spike, the browser
// process runs them once Chrome has started and prints "CRA-SPIKE PASS|FAIL <check>" lines, then quits.
#ifndef CRA_SPIKE_CHECKS_H_
#define CRA_SPIKE_CHECKS_H_

#include <memory>

class ChromeBrowserMainExtraParts;

namespace cra {

std::unique_ptr<ChromeBrowserMainExtraParts> MakeSpikeParts();

}  // namespace cra

#endif  // CRA_SPIKE_CHECKS_H_
