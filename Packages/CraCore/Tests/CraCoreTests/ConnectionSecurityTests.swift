import CraCore
import Testing

/// The Site Control Center's "Secure" badge follows the connection, not the URL (GitHub #90).
struct ConnectionSecurityTests {
    private func status(_ secure: Bool = true, cert: UInt = 0, content: UInt = 0) -> ConnectionSecurity.Status {
        ConnectionSecurity.Status(secureConnection: secure, certStatus: cert, contentStatus: content)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func aValidCertificateIsSecure() {
        #expect(ConnectionSecurity.isSecure(url: "https://example.com/", status: status()))
        // CERT_STATUS_IS_EV and CERT_STATUS_REV_CHECKING_ENABLED are notes, not errors.
        #expect(ConnectionSecurity.isSecure(url: "https://example.com/", status: status(cert: 1 << 16 | 1 << 17)))
    }

    /// An https page the user reached past a certificate warning reads "Not Secure".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func aCertificateErrorIsNotSecure() {
        #expect(!ConnectionSecurity.isSecure(url: "https://expired.badssl.com/", status: status(cert: 1 << 1)))
        #expect(!ConnectionSecurity.isSecure(url: "https://self-signed.badssl.com/", status: status(cert: 1 << 2)))
        #expect(!ConnectionSecurity.isSecure(url: "https://revoked.badssl.com/", status: status(cert: 1 << 6)))
    }

    /// Chrome ignores the two minor revocation errors.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func revocationThatCannotBeCheckedIsNotAnError() {
        #expect(ConnectionSecurity.isSecure(url: "https://example.com/", status: status(cert: 1 << 4 | 1 << 5)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func mixedContentIsNotSecure() {
        #expect(!ConnectionSecurity.isSecure(url: "https://example.com/", status: status(content: 1 << 0)))
        #expect(!ConnectionSecurity.isSecure(url: "https://example.com/", status: status(content: 1 << 1)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func plainHTTPIsNotSecure() {
        #expect(!ConnectionSecurity.isSecure(url: "http://example.com/", status: status(false)))
        #expect(!ConnectionSecurity.isSecure(url: "file:///tmp/a.html", status: status(false)))
    }

    /// Before a page commits (or for a sleeping tab) the scheme is all there is.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func withoutAStatusTheSchemeDecides() {
        #expect(ConnectionSecurity.isSecure(url: "https://example.com/", status: nil))
        #expect(!ConnectionSecurity.isSecure(url: "http://example.com/", status: nil))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/90")) func chromiumsOwnPagesAreSecure() {
        #expect(ConnectionSecurity.isSecure(url: "chrome://extensions", status: status(false)))
        #expect(ConnectionSecurity.isSecure(url: "chrome-extension://abc/options.html", status: nil))
    }
}
