// What Cra's start-up part (engine_main.mm) calls in the bridge (bridge.mm).
#ifndef CRA_BRIDGE_H_
#define CRA_BRIDGE_H_

namespace cra {

// Chrome is up (PostBrowserStart): runs what Cra's app asked for with +[CraCEFRuntime whenReady:].
void RunReadyBlocks();

// Chrome's main loop ended (PostMainMessageLoopRun): the bridge lets go of what it watches before Chrome tears it
// down (lists that must be empty by then).
void StopBridge();

}  // namespace cra

#endif  // CRA_BRIDGE_H_
