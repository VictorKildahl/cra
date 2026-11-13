#import "CraPreviewFetch.h"
#include <cstdio>
#include <string>

// Drive the production callback handlers without initializing Chromium. Real wire cancellation
// is a separate integration check; no test URL bypass is added to production Swift policy.
@interface CraPreviewRequest (CallbackContract)
- (void)tryStart;
- (void)receiveBytes:(const void*)bytes length:(size_t)length;
@end

static int checks = 0;
static void Expect(bool condition, const char* message) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main() {
    @autoreleasepool {
        __block int readiness = 0, completions = 0;
        __block NSInteger status = -1;
        __block NSUInteger size = 0;
        __block NSString* body = nil;
        CraPreviewRequest* request = [CraPreviewRequest requestURL:@"https://example.com/" maximumBytes:4 timeout:20 context:^{
            ++readiness;
            return CefRefPtr<CefRequestContext>(nullptr);
        } completion:^(NSInteger s, NSString*, NSString*, NSString*, NSString* text, NSUInteger count) {
            ++completions; status = s; body = text; size = count;
        }];
        Expect(readiness == 1 && completions == 0, "unready profile stays pending");
        [request receiveBytes:"12" length:2];
        [request receiveBytes:"34" length:2];
        Expect(completions == 0, "exact byte allowance remains valid");
        [request receiveBytes:"5" length:1];
        Expect(completions == 1 && status == 0 && body.length == 0 && size == 4, "oversized chunk is rejected before append and exposes no partial HTML");
        [request cancel];
        [request tryStart];
        [request receiveBytes:"late" length:4];
        Expect(completions == 1 && readiness == 1, "completion/cancellation/profile retry races finish exactly once");

        __block int capped = 0;
        CraPreviewRequest* maximum = [CraPreviewRequest requestURL:@"https://example.com/" maximumBytes:2 * 1024 * 1024 timeout:20 context:^{
            return CefRefPtr<CefRequestContext>(nullptr);
        } completion:^(NSInteger s, NSString*, NSString*, NSString*, NSString* text, NSUInteger count) {
            ++capped;
            Expect(s == 0 && text.length == 0 && count == 0, "oversized first chunk is never appended");
        }];
        std::string oversized(1024 * 1024 + 1, 'x');
        [maximum receiveBytes:oversized.data() length:oversized.size()];
        Expect(capped == 1, "native allowance cannot exceed the hard one-MiB ceiling");

        __block int cancelledCompletion = 0, cancelledReadiness = 0;
        CraPreviewRequest* cancelled = [CraPreviewRequest requestURL:@"https://example.com/" maximumBytes:1024 timeout:20 context:^{
            ++cancelledReadiness;
            return CefRefPtr<CefRequestContext>(nullptr);
        } completion:^(NSInteger s, NSString*, NSString*, NSString*, NSString* text, NSUInteger count) {
            ++cancelledCompletion;
            Expect(s == 0 && text.length == 0 && count == 0, "cancelled readiness cannot return page content");
        }];
        [cancelled cancel];
        [cancelled tryStart];
        [cancelled cancel];
        Expect(cancelledCompletion == 1 && cancelledReadiness == 1, "cancel before profile readiness prevents later creation");

        __block int expired = 0;
        [CraPreviewRequest requestURL:@"https://example.com/" maximumBytes:1024 timeout:0 context:^{
            Expect(false, "expired request cannot resolve or create a profile");
            return CefRefPtr<CefRequestContext>(nullptr);
        } completion:^(NSInteger s, NSString*, NSString*, NSString*, NSString*, NSUInteger) {
            ++expired; Expect(s == 0, "expired native deadline finishes as failure");
        }];
        Expect(expired == 1, "expired creation completes synchronously once");

        __weak CraPreviewRequest* weak;
        @autoreleasepool {
            CraPreviewRequest* pending = [CraPreviewRequest requestURL:@"https://example.com/" maximumBytes:4 timeout:20 context:^{
                return CefRefPtr<CefRequestContext>(nullptr);
            } completion:^(NSInteger, NSString*, NSString*, NSString*, NSString*, NSUInteger) {}];
            weak = pending;
        }
        Expect(weak == nil, "readiness polling and deadline do not retain an abandoned request");
        printf("Link summary CEF callback contract: %d checks passed\n", checks);
    }
}
