// What Cra's start-up part (engine_main.mm) calls in the bridge (bridge.mm).
#ifndef CRA_BRIDGE_H_
#define CRA_BRIDGE_H_

#include <string>

namespace base {
class DictValue;
}  // namespace base

namespace content {
class WebContents;
}  // namespace content

namespace cra {

// Chrome is up (PostBrowserStart): runs what Cra's app asked for with +[CraCEFRuntime whenReady:].
void RunReadyBlocks();

// Chrome's main loop ended (PostMainMessageLoopRun): the bridge lets go of what it watches before Chrome tears it
// down (lists that must be empty by then).
void StopBridge();

// Cra.debug* methods (page_protocol.mm) that let a scenario reach what Chrome does to the bridge's hidden pieces.
// False when `method` is none of them.
bool HandleDebugMethod(content::WebContents* contents,
                       const std::string& method,
                       const base::DictValue* params,
                       base::DictValue* result,
                       std::string* error);

}  // namespace cra

#endif  // CRA_BRIDGE_H_
