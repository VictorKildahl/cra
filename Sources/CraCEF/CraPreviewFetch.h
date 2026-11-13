// Preview transport internals; the public Swift surface is CraCEF.h.
#import "include/CraCEF.h"
#include "include/cef_request_context.h"

NS_ASSUME_NONNULL_BEGIN
@interface CraPreviewRequest (Creation)
+ (instancetype)requestURL:(NSString*)url maximumBytes:(NSUInteger)maximumBytes timeout:(NSTimeInterval)timeout
                  context:(CefRefPtr<CefRequestContext> (^)(void))context
               completion:(void (^)(NSInteger, NSString*, NSString*, NSString*, NSString*, NSUInteger))completion;
@end
NS_ASSUME_NONNULL_END
