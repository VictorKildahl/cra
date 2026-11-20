#include "ContentBlockerShim.h"
#include "CraContentBlocker.h"

extern "C" size_t cra_blocker_load(const char* text) {
    cra_blocker::Publish(cra_blocker::ParseList(text));
    cra_blocker::Enabled().store(true);
    return cra_blocker::Count();
}

extern "C" bool cra_blocker_should_block(const char* request_host, const char* page_host) {
    return cra_blocker::ShouldBlock(cra_blocker::NormalizeHost(request_host), cra_blocker::NormalizeHost(page_host));
}
