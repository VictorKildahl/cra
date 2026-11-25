import CraCore
import Foundation
import Testing

/// What Cra hands off to an iPhone (GitHub #745): the front page's web address, never an incognito window's.
struct HandoffPageTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/745"))
    func aWebPageIsOfferedToOtherDevices() {
        #expect(HandoffPage.url(for: "https://github.com/VictorKildahl/cra/issues/745", offTheRecord: false)?.absoluteString
            == "https://github.com/VictorKildahl/cra/issues/745")
        #expect(HandoffPage.url(for: "http://127.0.0.1:8080/page.html?n=1", offTheRecord: false)?.host == "127.0.0.1")
        #expect(HandoffPage.url(for: "HTTPS://Example.com/", offTheRecord: false) != nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/745"))
    func pagesAnIPhoneCantOpenAndIncognitoOnesStayOnTheMac() {
        #expect(HandoffPage.url(for: "https://example.com/", offTheRecord: true) == nil)
        for address in ["chrome://settings", "cra://newtab", "file:///Users/x/a.html", "data:text/html,hi", "about:blank",
                        "chrome-extension://abc/popup.html", "", "https://", "not a url"] {
            #expect(HandoffPage.url(for: address, offTheRecord: false) == nil, "\(address)")
        }
    }
}
