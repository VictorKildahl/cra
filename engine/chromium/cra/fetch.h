// A GET made by the browser with a profile's cookies, as a page of that profile would make it (the CEF bridge's
// fetchURL): how live folders read github.com with the user's own session.
#ifndef CRA_FETCH_H_
#define CRA_FETCH_H_

#import <Foundation/Foundation.h>

class Profile;
class GURL;

namespace cra {

// HTTP status (0 when the request failed), the URL after redirects, the MIME type and the body as UTF-8, on the
// main queue. `restricted` (a live-folder plug-in's fetch): redirects aren't followed (the status and Location
// come back), the body stops at 4 MB and the request at 20 s.
using FetchDone = void (^)(NSInteger status, NSString* finalURL, NSString* mimeType, NSString* body);
void Fetch(Profile* profile, const GURL& url, NSDictionary<NSString*, NSString*>* headers, bool restricted,
           FetchDone done);

}  // namespace cra

#endif  // CRA_FETCH_H_
