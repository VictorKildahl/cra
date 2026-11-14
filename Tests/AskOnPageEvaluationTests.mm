#import <Foundation/Foundation.h>

// Only the transport is controlled. The production isolated-evaluate methods are included verbatim.
#define CEF_REQUIRE_UI_THREAD() do {} while (0)
static const int TID_UI = 0;
static bool CefCurrentlyOn(int) { return true; }
@interface CraBrowser : NSObject
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* pending;
- (void)sendDevToolsMethod:(NSString*)method params:(NSString*)params completion:(void (^)(NSString*, NSString*))completion;
- (void)evaluateInIsolatedWorld:(NSString*)world params:(NSString*)params completion:(void (^)(NSString*, NSString*))completion;
- (void)evaluateInIsolatedWorld:(NSString*)world params:(NSString*)params ifCurrent:(BOOL (^)(void))current completion:(void (^)(NSString*, NSString*))completion;
@end
@implementation CraBrowser
- (instancetype)init { if ((self = [super init])) _pending = [NSMutableArray array]; return self; }
- (void)sendDevToolsMethod:(NSString*)method params:(NSString*)params completion:(void (^)(NSString*, NSString*))completion {
    [_pending addObject:@{@"method": method, @"params": params, @"completion": [completion copy]}];
}
#include "QuoteEvaluation+Production.mm"
@end
static int checks = 0;
static void expect(BOOL value, NSString* message) { ++checks; if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void reply(CraBrowser* browser, NSString* expectedMethod, NSString* result) {
    NSDictionary* pending = browser.pending.firstObject;
    expect([pending[@"method"] isEqual:expectedMethod], @"the production setup uses the expected transport stage");
    [browser.pending removeObjectAtIndex:0];
    ((void (^)(NSString*, NSString*))pending[@"completion"])(result, nil);
}
// promise: #393
static void guardedSetupRejectsRetiredOwners() {
    for (int retireAt = 0; retireAt < 4; ++retireAt) {
        CraBrowser* browser = [CraBrowser new];
        __block int authorizations = 0, completions = 0;
        __block BOOL rejected = NO;
        [browser evaluateInIsolatedWorld:@"cra" params:@"{\"expression\":\"true\",\"returnByValue\":true}"
            ifCurrent:^BOOL { return authorizations++ < retireAt; }
            completion:^(NSString* result, NSString* error) { ++completions; rejected = result == nil && [error isEqual:@"retired evaluation"]; }];
        if (retireAt > 0) reply(browser, @"Page.getFrameTree", @"{\"frameTree\":{\"frame\":{\"id\":\"captured-frame\"}}}");
        if (retireAt > 1) reply(browser, @"Page.createIsolatedWorld", @"{\"executionContextId\":42}");
        expect(completions == 1 && rejected && browser.pending.count == 0,
            @"entry/frame/world/final-dispatch invalidation must reject once without issuing renderer effects");
    }
    CraBrowser* browser = [CraBrowser new];
    __block int completions = 0;
    [browser evaluateInIsolatedWorld:@"cra" params:@"{\"expression\":\"true\",\"returnByValue\":true}" ifCurrent:^BOOL { return YES; }
        completion:^(NSString* result, NSString* error) { ++completions; expect([result isEqual:@"verified-result"] && error == nil, @"a current committed result completes unchanged"); }];
    reply(browser, @"Page.getFrameTree", @"{\"frameTree\":{\"frame\":{\"id\":\"captured-frame\"}}}");
    reply(browser, @"Page.createIsolatedWorld", @"{\"executionContextId\":42}");
    NSDictionary* params = [NSJSONSerialization JSONObjectWithData:[browser.pending[0][@"params"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    expect([params[@"contextId"] isEqual:@42] && [params[@"expression"] isEqual:@"true"], @"the effect is committed to the resolved isolated context");
    reply(browser, @"Runtime.evaluate", @"verified-result");
    expect(completions == 1, @"a current committed operation completes exactly once");
}
int main() { @autoreleasepool { guardedSetupRejectsRetiredOwners(); printf("Ask isolated evaluation: %d production setup checks passed\n", checks); } }
