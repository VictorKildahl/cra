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
