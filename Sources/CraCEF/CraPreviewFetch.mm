#import "CraPreviewFetch.h"
#include "include/cef_urlrequest.h"
#include <algorithm>
#include <cmath>
#include <string>

@interface CraPreviewRequest ()
- (void)tryStart;
- (void)receiveBytes:(const void*)bytes length:(size_t)length;
- (void)completed:(CefRefPtr<CefURLRequest>)request;
@end

/// CEF delivers URLRequest callbacks on their creating thread (cef_urlrequest.h). The only
/// exception is auth, which declines credentials on IO without touching the main-thread owner.
class PreviewFetchClient : public CefURLRequestClient {
public:
    explicit PreviewFetchClient(CraPreviewRequest* owner) : owner_(owner) {}
    void OnDownloadData(CefRefPtr<CefURLRequest> request, const void* data, size_t length) override {
        [owner_ receiveBytes:data length:length];
    }
    void OnRequestComplete(CefRefPtr<CefURLRequest> request) override { [owner_ completed:request]; }
    void OnUploadProgress(CefRefPtr<CefURLRequest>, int64_t, int64_t) override {}
    void OnDownloadProgress(CefRefPtr<CefURLRequest>, int64_t, int64_t) override {}
    bool GetAuthCredentials(bool, const CefString&, int, const CefString&, const CefString&,
                            CefRefPtr<CefAuthCallback>) override { return false; }
private:
    __weak CraPreviewRequest* owner_;
    IMPLEMENT_REFCOUNTING(PreviewFetchClient);
};

@implementation CraPreviewRequest {
    NSString* _url;
    CefRefPtr<CefRequestContext> (^_context)(void);
    void (^_completion)(NSInteger, NSString*, NSString*, NSString*, NSString*, NSUInteger);
    NSTimer* _deadline;
    CefRefPtr<CefURLRequest> _request;
    std::string _body;
    size_t _maximumBytes;
    BOOL _finished;
}

+ (instancetype)requestURL:(NSString*)url maximumBytes:(NSUInteger)maximumBytes timeout:(NSTimeInterval)timeout
                  context:(CefRefPtr<CefRequestContext> (^)(void))context
               completion:(void (^)(NSInteger, NSString*, NSString*, NSString*, NSString*, NSUInteger))completion {
    NSAssert(NSThread.isMainThread, @"Preview requests are created on the CEF UI thread");
    CraPreviewRequest* operation = [self new];
    operation->_url = [url copy];
    operation->_maximumBytes = std::min((size_t)maximumBytes, (size_t)1024 * 1024);
    operation->_context = [context copy];
    operation->_completion = [completion copy];
    if (!std::isfinite(timeout) || timeout <= 0) { [operation cancel]; return operation; }
    __weak CraPreviewRequest* weak = operation;
    operation->_deadline = [NSTimer timerWithTimeInterval:std::min(timeout, 20.0) repeats:NO block:^(NSTimer*) { [weak cancel]; }];
    [NSRunLoop.mainRunLoop addTimer:operation->_deadline forMode:NSRunLoopCommonModes];
    [operation tryStart];
    return operation;
}

- (void)tryStart {
    NSAssert(NSThread.isMainThread, @"Preview requests stay on their creating thread");
    if (_finished || _request) return;
    CefRefPtr<CefRequestContext> context = _context();
    if (!context) {
        __weak CraPreviewRequest* weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weak tryStart]; });
        return;
    }
    CefRefPtr<CefRequest> request = CefRequest::Create();
    request->SetURL(CefString(_url.UTF8String));
    request->SetMethod("GET");
    request->SetFlags(UR_FLAG_ALLOW_STORED_CREDENTIALS | UR_FLAG_SKIP_CACHE | UR_FLAG_STOP_ON_REDIRECT | UR_FLAG_NO_RETRY_ON_5XX);
    request->SetFirstPartyForCookies(CefString(_url.UTF8String));
    CefRequest::HeaderMap headers;
    headers.insert({"Accept", "text/html,application/xhtml+xml"});
    request->SetHeaderMap(headers);
    CefRefPtr<CefURLRequest> active = CefURLRequest::Create(request, new PreviewFetchClient(self), context);
    // A synchronous completion must not reinstall a finished request.
    if (_finished) { if (active) active->Cancel(); return; }
    _request = active;
    if (!active) [self cancel];
}

- (void)receiveBytes:(const void*)bytes length:(size_t)length {
    NSAssert(NSThread.isMainThread, @"Preview bytes arrive on their creating thread");
    if (_finished || length == 0) return;
    if (length > _maximumBytes - _body.size()) { [self cancel]; return; }
    _body.append(static_cast<const char*>(bytes), length);
}

- (void)completed:(CefRefPtr<CefURLRequest>)request {
    NSAssert(NSThread.isMainThread, @"Preview completion arrives on its creating thread");
    if (_finished) return;
    CefRefPtr<CefResponse> response = request->GetResponse();
    bool redirect = response && response->GetStatus() >= 300 && response->GetStatus() < 400;
    if (!response || (request->GetRequestStatus() != UR_SUCCESS && !redirect)) { [self cancel]; return; }
    NSString* finalURL = [NSString stringWithUTF8String:response->GetURL().ToString().c_str()];
    NSString* location = [NSString stringWithUTF8String:response->GetHeaderByName("Location").ToString().c_str()] ?: @"";
    NSString* mime = [NSString stringWithUTF8String:response->GetMimeType().ToString().c_str()] ?: @"";
    NSString* body = [[NSString alloc] initWithBytes:_body.data() length:_body.size() encoding:NSUTF8StringEncoding] ?: @"";
    [self finish:response->GetStatus() finalURL:finalURL.length ? finalURL : _url location:location mime:mime body:body cancel:NO];
}

- (void)finish:(NSInteger)status finalURL:(NSString*)finalURL location:(NSString*)location mime:(NSString*)mime body:(NSString*)body cancel:(BOOL)cancel {
    if (_finished) return;
    _finished = YES;
    [_deadline invalidate];
    _deadline = nil;
    _context = nil;
    auto completion = _completion;
    _completion = nil;
    CefRefPtr<CefURLRequest> request = std::move(_request);
    NSUInteger receivedBytes = _body.size();
    std::string().swap(_body);
    // Clear state before Cancel: CEF may synchronously report completion while cancelling.
    if (cancel && request) request->Cancel();
    if (completion) completion(status, finalURL, location, mime, body, receivedBytes);
}

- (void)cancel {
    NSAssert(NSThread.isMainThread, @"Preview cancellation uses the CEF UI thread");
    [self finish:0 finalURL:_url ?: @"" location:@"" mime:@"" body:@"" cancel:YES];
}

- (void)dealloc {
    [_deadline invalidate];
    // URLRequest methods must run on the creating thread, even if a caller releases its token
    // elsewhere. The client holds its owner weakly, so this cannot reenter a dying operation.
    CefRefPtr<CefURLRequest> request = std::move(_request);
    if (request) dispatch_async(dispatch_get_main_queue(), ^{ request->Cancel(); });
}
@end
