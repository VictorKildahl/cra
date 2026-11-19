import Foundation

/// What the iPhone app does when a page fails before anything of it showed (WebKit's provisional
/// navigation failed). Arc Search has an error screen for such a page (a "hostname not found"
/// screen is recorded); its wording isn't, so the page says what Cra for Mac's WebKit tabs say.
public enum MobileLoadFailure {
    public enum Answer: Equatable {
        /// Stopped on purpose (a new address, a download, a link handed to another app).
        case nothing
        /// The certificate couldn't be verified: the warning that lets the user go on (Arc Search 1.12).
        case certificateWarning
        /// Any other failure the network reports, or a load WebKit refuses: a page that says the
        /// page couldn't load, and why. Before #568 this left the tab a blank white page.
        case errorPage
    }

    public static let certificateCodes = [
        NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed,
    ]

    /// WebKit's own errors' domain on Apple platforms. The codes are in WebKit's
    /// Source/WebKit/Shared/API/APIError.h.
    public static let webKitErrorDomain = "WebKitErrorDomain"

    /// WebKit codes for a load that something else took over, so the tab shows that instead:
    /// 102 FrameLoadInterruptedByPolicyChange (a download, a link another app opened), 105
    /// FrameLoadBlockedByContentFilter (WebKit then loads the filter's own page), 204
    /// PlugInWillHandleLoad (a plug-in or media document), 302 Network::Cancelled. Every other
    /// WebKit code is WebKit refusing the load, such as 103 CannotUseRestrictedPort.
    public static let takenOverCodes = [102, 105, 204, 302]

    public static func answer(domain: String, code: Int) -> Answer {
        switch domain {
        case NSURLErrorDomain:
            if code == NSURLErrorCancelled { return .nothing }
            return certificateCodes.contains(code) ? .certificateWarning : .errorPage
        case webKitErrorDomain:
            return takenOverCodes.contains(code) ? .nothing : .errorPage
        default:
            // WKErrorDomain (the web process, the API) and WebKitInternal, whose one code 0 also
            // means "Loading in a new process".
            return .nothing
        }
    }

    /// WebKit's 101, CannotShowURL: what WebKit says for an address it has no way to load.
    public static let cannotShowURLCode = 101

    /// The answer for a failed load of `address`. Another app's address (mailto:, tel:, a custom
    /// scheme) that WebKit can't load (-1002 "unsupported URL", or WebKit's 101) says nothing and
    /// the page stays: it goes to its app before WebKit sees it (`MobileExternalLinks`), and this
    /// keeps the error page away should one get through (TestFlight 1086 showed "mailto:…:
    /// unsupported URL" in place of the page). On an http(s) address, or without one, the
    /// answer is the code's.
    public static func answer(domain: String, code: Int, address: String?) -> Answer {
        let unsupported = (domain == NSURLErrorDomain && code == NSURLErrorUnsupportedURL)
            || (domain == webKitErrorDomain && code == cannotShowURLCode)
        if unsupported, let address, MobileExternalLinks.goesOut(address) { return .nothing }
        return answer(domain: domain, code: code)
    }

    /// A main-frame load to an address WebKit refuses gets the error page before WebKit tries it.
    /// iOS 26.5's WebKit commits an empty about:blank for it (`isRefusedAsBlank`), so the error
    /// page answered after the fact came after that blank in the history, and Back landed on it.
    /// Going back or forward is left to WebKit (the page may come from its cache), with the
    /// blank-page answer behind it. A link in a page to such an address never gets here: WebKit
    /// drops it in the page.
    public static func answersBeforeLoading(_ address: String, isMainFrame: Bool, isBackForward: Bool) -> Bool {
        isMainFrame && !isBackForward && webKitRefuses(address)
    }

    /// WebKit's 103, CannotUseRestrictedPort, with WebKit's own description (WebErrors.cpp
    /// `blockedError`). It covers an address of only zeros as well as a restricted port.
    public static let restrictedPortCode = 103
    public static let restrictedPortMessage = "Not allowed to use restricted network port"

    /// The ports WebKit never connects to: WTF/wtf/URL.cpp `portAllowed`, the Fetch spec's list
    /// with port 0 and Apple's additions.
    public static let restrictedPorts: Set<Int> = [
        0, 1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104, 109,
        110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526, 530,
        531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 4190,
        5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080,
    ]

    /// WebKit refuses to load this address: a restricted port (`portAllowed`, which lets a file
    /// address and FTP's own 21 and 22 through), or a host of only zeros (WebCore DNS.cpp
    /// `isIPAddressDisallowed`).
    public static func webKitRefuses(_ address: String) -> Bool {
        guard let url = URLComponents(string: address), let scheme = url.scheme?.lowercased(), scheme != "file" else { return false }
        if let port = url.port, restrictedPorts.contains(port), !(scheme == "ftp" && (port == 21 || port == 22)) { return true }
        guard let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return v4.s_addr == 0 }
        if inet_pton(AF_INET6, host, &v6) == 1 { return withUnsafeBytes(of: &v6) { $0.allSatisfy { $0 == 0 } } }
        return false
    }

    /// iOS 26.5's WebKit doesn't fail a load it refuses that way: it commits an empty about:blank,
    /// and the delegate hears of no failure. WebKit fails it with 103 since June 2026 (bug 317357);
    /// until then that blank page, committed for an address WebKit refuses, is the refusal.
    public static func isRefusedAsBlank(requested: String, committed: String) -> Bool {
        committed == "about:blank" && webKitRefuses(requested)
    }

    public static let heading = "This page couldn’t load"

    /// The error page, shown at the failing address so Reload tries it again.
    public static func page(host: String, message: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta name="color-scheme" content="light dark">
        <title>\(esc(host))</title>
        <style>body{font:17px -apple-system,system-ui,sans-serif;margin:0;display:grid;place-items:center;min-height:100vh;color:CanvasText;background:Canvas}
        div{max-width:520px;padding:24px}h1{font-size:22px;font-weight:600;margin:0 0 8px}p{opacity:.7;margin:0}</style>
        <div><h1>\(heading)</h1><p>\(esc(host)): \(esc(message))</p></div>
        """
    }
}
