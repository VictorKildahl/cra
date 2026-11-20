// C entry points into Sources/CraCEF/CraContentBlocker.h, the engine's ad and tracker matching, for
// Tests/ContentBlockerTests.swift (scripts/test-content-blocker.sh).
#pragma once
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Parses a list file's text, publishes it as the engine's set and turns blocking on. Returns its size.
size_t cra_blocker_load(const char* text);
/// The engine's decision for one request (hosts as URLs give them; they're normalized here).
bool cra_blocker_should_block(const char* request_host, const char* page_host);

#ifdef __cplusplus
}
#endif
