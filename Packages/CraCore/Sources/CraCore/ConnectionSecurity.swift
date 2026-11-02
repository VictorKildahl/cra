import Foundation

/// The Site Control Center's connection badge, "Secure" or "Not Secure" (GitHub #90): Chrome's
/// security level, read from the page's SSL status rather than its URL, in Arc's two states.
///
/// An https page whose certificate has an error (the user went past the warning, or the warning
/// page itself) or that showed or ran http content is not secure. Chromium's own pages are.
public enum ConnectionSecurity {
    /// Chromium's SSL status of the page on screen (CefSSLStatus).
    public struct Status: Equatable, Sendable {
        /// The page came over a connection with a certificate.
        public var secureConnection: Bool
        /// net::CertStatus bits.
        public var certStatus: UInt
        /// net::SSLStatus::ContentStatus bits.
        public var contentStatus: UInt

        public init(secureConnection: Bool, certStatus: UInt, contentStatus: UInt) {
            self.secureConnection = secureConnection
            self.certStatus = certStatus
            self.contentStatus = contentStatus
        }
    }

    /// net::CERT_STATUS_ALL_ERRORS, less the two minor errors Chrome ignores
    /// (CERT_STATUS_NO_REVOCATION_MECHANISM, CERT_STATUS_UNABLE_TO_CHECK_REVOCATION).
    static let certErrors: UInt = 0xFF00_FFFF & ~UInt(1 << 4 | 1 << 5)
    /// SSL_CONTENT_DISPLAYED_INSECURE_CONTENT, SSL_CONTENT_RAN_INSECURE_CONTENT.
    static let insecureContent: UInt = 1 << 0 | 1 << 1

    /// `status` is nil before a page has committed (or with no page at all): the URL decides.
    public static func isSecure(url: String, status: Status?) -> Bool {
        if url.hasPrefix("chrome://") || url.hasPrefix("chrome-extension://") { return true }
        guard let status else { return url.hasPrefix("https://") }
        return status.secureConnection && status.certStatus & certErrors == 0 && status.contentStatus & insecureContent == 0
    }
}
