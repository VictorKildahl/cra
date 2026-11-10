#import "BrowserBridge.h"

@implementation CraBrowser
@synthesize delegate = _delegate;
@end

@implementation EaselColorObserver
- (instancetype)init {
    if ((self = [super init])) { _background = @""; _theme = @""; }
    return self;
}
- (void)browser:(CraBrowser *)browser didReportBackgroundColor:(NSString *)hex { self.background = hex; }
- (void)browser:(CraBrowser *)browser didReportThemeColor:(NSString *)hex { self.theme = hex; }
- (void)browser:(CraBrowser *)browser didChangeTitle:(NSString *)title {}
- (void)browser:(CraBrowser *)browser didChangeURL:(NSString *)url {}
- (void)browser:(CraBrowser *)browser didChangeLoading:(BOOL)loading canGoBack:(BOOL)back canGoForward:(BOOL)forward {}
- (void)browser:(CraBrowser *)browser didFinishLoadingURL:(NSString *)url title:(NSString *)title statusCode:(NSInteger)code {}
- (void)browserDidClose:(CraBrowser *)browser {}
@end
