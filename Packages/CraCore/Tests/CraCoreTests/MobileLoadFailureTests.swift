import CraCore
import Foundation
import Testing

/// What the iPhone app does when a page fails to load before anything of it showed.
struct MobileLoadFailureTests {
    /// GitHub #568: App Transport Security refused every http:// page (-1022) and only certificate
    /// errors said anything, so the tab stayed a blank white page. A failure the network reports
    /// now puts up a page that says so.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func aNetworkFailureShowsAnErrorPage() {
        for code in [NSURLErrorAppTransportSecurityRequiresSecureConnection, NSURLErrorCannotFindHost,
                     NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut] {
            #expect(MobileLoadFailure.answer(domain: NSURLErrorDomain, code: code) == .errorPage)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func aCertificateFailureStillAsksAndAStoppedLoadSaysNothing() {
        for code in [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
                     NSURLErrorSecureConnectionFailed] {
            #expect(MobileLoadFailure.answer(domain: NSURLErrorDomain, code: code) == .certificateWarning)
        }
        // A new address, a download or a link handed to another app stops the load: not a failure.
        #expect(MobileLoadFailure.answer(domain: NSURLErrorDomain, code: NSURLErrorCancelled) == .nothing)
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 102) == .nothing)
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 204) == .nothing)
    }

    /// GitHub #568, follow-up: a load WebKit refuses itself left the tab blank, because only the
    /// network's own failures got the page. WebKit's codes are in its source,
    /// Source/WebKit/Shared/API/APIError.h, all in WebKitErrorDomain on Apple platforms
    /// (Source/WebKit/Shared/WebErrors.cpp makes them).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func aLoadWebKitRefusesShowsTheErrorPage() {
        let refusals = [
            100, // CannotShowMIMEType
            101, // CannotShowURL: an invalid address
            103, // CannotUseRestrictedPort: http://127.0.0.1:1/, or an address of only zeros
            104, // FrameLoadBlockedByContentBlocker: the page itself on a block list
            106, // FrameLoadBlockedByRestrictions: the device's restrictions
            200, 201, 202, 203, 205, // plug-ins that can't run
            300, // Internal
            304, // HTTPSUpgradeRedirectLoop
            305, // HTTPNavigationWithHTTPSOnlyError
        ]
        for code in refusals {
            #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: code) == .errorPage, "WebKitErrorDomain \(code)")
        }
    }

    /// Loads stopped on purpose, or taken over by something else, still say nothing: the tab shows
    /// what took the load over.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func aLoadSomethingElseTookOverSaysNothing() {
        #expect(MobileLoadFailure.answer(domain: NSURLErrorDomain, code: NSURLErrorCancelled) == .nothing)
        // FrameLoadInterruptedByPolicyChange: a download, or a link another app opened (seen for a
        // Content-Disposition: attachment response and an application/octet-stream one).
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 102) == .nothing)
        // FrameLoadBlockedByContentFilter: WebKit then loads the filter's own blocked page
        // (FrameLoader: contentFilterWillHandleProvisionalLoadFailure).
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 105) == .nothing)
        // PlugInWillHandleLoad: a plug-in or media document handles the load itself.
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 204) == .nothing)
        // Network::Cancelled, WebKit's own cancellation.
        #expect(MobileLoadFailure.answer(domain: "WebKitErrorDomain", code: 302) == .nothing)
        // WebKit's other domains (WKErrorDomain's process and API errors, WebKitInternal) stay as
        // they were: WebKitInternal code 0 also means "Loading in a new process".
        #expect(MobileLoadFailure.answer(domain: "WKErrorDomain", code: 2) == .nothing)
        #expect(MobileLoadFailure.answer(domain: "WebKitInternal", code: 0) == .nothing)
    }

    /// GitHub #568, follow-up: iOS 26.5's WebKit doesn't fail a load to a restricted port or to an
    /// address of only zeros. It commits an empty about:blank instead (seen for
    /// http://127.0.0.1:1/, http://127.0.0.1:6000/, https://127.0.0.1:5061/ and
    /// http://0.0.0.0:18799/), so no failure ever reached the tab. WebKit changed that in June 2026
    /// (bug 317357) to fail with 103; until every iPhone has it, that blank is the same refusal.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func aRefusedAddressAnsweredWithABlankPageIsARefusal() {
        for address in ["http://127.0.0.1:1/", "http://127.0.0.1:6000/", "https://127.0.0.1:5061/", "http://0.0.0.0:18799/",
                        "http://example.com:25/mail", "http://[::]:8080/", "http://example.com:10080"] {
            #expect(MobileLoadFailure.isRefusedAsBlank(requested: address, committed: "about:blank"), "\(address)")
        }
        // The blank page is the refusal only for an address WebKit refuses ...
        for address in ["http://127.0.0.1:4/", "http://127.0.0.1:18765/plain", "https://example.com/", "http://example.com:8080/",
                        "about:blank", "file:///tmp/x:1", "ftp://example.com:21/x"] {
            #expect(!MobileLoadFailure.isRefusedAsBlank(requested: address, committed: "about:blank"), "\(address)")
        }
        // ... and only when the blank page is what committed: the error page at the address isn't.
        #expect(!MobileLoadFailure.isRefusedAsBlank(requested: "http://127.0.0.1:1/", committed: "http://127.0.0.1:1/"))
    }

    /// The page names the host and the system's reason, as Cra for Mac's WebKit tabs do, and
    /// escapes both.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/568"))
    func theErrorPageNamesTheHostAndTheReason() {
        let page = MobileLoadFailure.page(host: "example.com", message: "Could not connect to the server.")
        #expect(page.contains("<h1>This page couldn’t load</h1>"))
        #expect(page.contains("<p>example.com: Could not connect to the server.</p>"))
        #expect(page.contains("<title>example.com</title>"))
        #expect(page.contains("width=device-width"))
        let hostile = MobileLoadFailure.page(host: "a<b>", message: "x & <script>")
        #expect(hostile.contains("a&lt;b&gt;: x &amp; &lt;script&gt;"))
        #expect(!hostile.contains("<script>"))
    }
}
