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
        /// Any other failure the network reports: a page that says the page couldn't load, and why.
        /// Before #568 this left the tab a blank white page.
        case errorPage
    }

    public static let certificateCodes = [
        NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed,
    ]

    public static func answer(domain: String, code: Int) -> Answer {
        // WebKit's own errors (102 interrupted by a policy change, 204 handled by a plug-in) are
        // loads it stopped itself, as is a cancelled one.
        guard domain == NSURLErrorDomain, code != NSURLErrorCancelled else { return .nothing }
        return certificateCodes.contains(code) ? .certificateWarning : .errorPage
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
