import CraCore
import Foundation
import Testing

/// What a Little Window's address pill reads, and whether it warns (#330).
struct LittleAddressTests {
    /// Arc 1.172.1 (10 Nov 2026): for http://cra-measure.lvh.me:47110/page?e=link1 the pill read
    /// `cra-measure.lvh.me`, with no port, path or query.
    @Test func readsTheHostAndNothingElse() {
        #expect(LittleAddress.host(of: "http://cra-measure.lvh.me:47110/page?e=link1") == "cra-measure.lvh.me")
        #expect(LittleAddress.host(of: "https://example.com/a/b?c=d#e") == "example.com")
        #expect(LittleAddress.host(of: "https://example.com") == "example.com")
    }

    /// The main window's URL pill leaves the www out too (SidebarView), and only a leading one.
    @Test func leavesTheLeadingWWWOut() {
        #expect(LittleAddress.host(of: "https://www.example.com/x") == "example.com")
        #expect(LittleAddress.host(of: "https://wwwx.example.com/") == "wwwx.example.com")
        #expect(LittleAddress.host(of: "https://news.www.example.com/") == "news.www.example.com")
    }

    @Test func keepsAnIPv6AddressInItsBrackets() {
        #expect(LittleAddress.host(of: "http://[::1]:8080/index.html") == "[::1]")
    }

    @Test func neverShowsASignIn() {
        #expect(LittleAddress.host(of: "https://reader:secret@example.com/feed") == "example.com")
    }

    /// Pages without a host keep the text they had: about:blank while a first response is awaited
    /// (Arc shows it too), an internal page, a file.
    @Test func leavesPagesWithoutAHostToTheCaller() {
        for url in ["about:blank", "chrome://version", "file:///Users/me/notes.html", "view-source:https://example.com/",
                    "data:text/html,hello", "cra://settings", "", "https:///path"] {
            #expect(LittleAddress.host(of: url) == nil, "\(url)")
        }
    }

    /// Arc swaps the magnifier for an open padlock on a page that isn't served over https.
    @Test func warnsOnlyAboutPlainHTTP() {
        #expect(LittleAddress.isInsecure("http://cra-measure.lvh.me:47110/page?e=link1"))
        #expect(LittleAddress.isInsecure("HTTP://EXAMPLE.COM/"))
        #expect(!LittleAddress.isInsecure("https://example.com/"))
        for url in ["about:blank", "chrome://version", "file:///Users/me/notes.html", "data:text/html,hello", "http:", ""] {
            #expect(!LittleAddress.isInsecure(url), "\(url)")
        }
    }
}
