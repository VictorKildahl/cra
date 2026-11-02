import CraCore
import Testing

/// Chromium's secure DNS setting as the log and Export Diagnostics show it (#110).
struct SecureDNSTests {
    @Test(arguments: [
        // Chromium's default, and Arc's: no provider, so the system resolver.
        ("automatic", "", "automatic, no provider (system resolver)"),
        // What Chromium writes when Google is picked in chrome://settings/security.
        ("secure", "https://dns.google/dns-query{?dns}", "secure via dns.google"),
        ("automatic", "https://chrome.cloudflare-dns.com/dns-query", "automatic via chrome.cloudflare-dns.com"),
        ("secure", "", "secure, no provider"),
        ("off", "https://dns.google/dns-query{?dns}", "off"),
        ("", "", "unset"),
    ])
    func line(mode: String, templates: String, line: String) {
        #expect(SecureDNS(mode: mode, templates: templates).line == line)
    }

    @Test func customTemplatesKeepOnlyTheirHost() {
        let dns = SecureDNS(mode: "secure", templates: "https://dns.nextdns.io/a1b2c3/MacBook")
        #expect(dns.servers == ["dns.nextdns.io"])
        #expect(!dns.line.contains("a1b2c3"))
    }

    @Test func severalTemplatesAreOneServerEach() {
        let dns = SecureDNS(mode: "secure", templates: "https://dns.google/dns-query{?dns}\nhttps://DNS.google/resolve  https://dns.quad9.net/dns-query")
        #expect(dns.servers == ["dns.google", "dns.quad9.net"])
    }

    @Test func aTemplateWithoutAHostIsNamedButNotShown() {
        #expect(SecureDNS(mode: "secure", templates: "not a url/secret").line == "secure via a custom server")
    }
}
