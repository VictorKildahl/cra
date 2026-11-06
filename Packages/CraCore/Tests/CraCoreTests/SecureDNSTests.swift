import CraCore
import Testing

/// Chromium's secure DNS setting as the log and Export Diagnostics show it (#110).
struct SecureDNSTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/110"), arguments: [
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

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/110")) func customTemplatesKeepOnlyTheirHost() {
        let dns = SecureDNS(mode: "secure", templates: "https://dns.nextdns.io/a1b2c3/MacBook")
        #expect(dns.servers == ["dns.nextdns.io"])
        #expect(!dns.line.contains("a1b2c3"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/110")) func severalTemplatesAreOneServerEach() {
        let dns = SecureDNS(mode: "secure", templates: "https://dns.google/dns-query{?dns}\nhttps://DNS.google/resolve  https://dns.quad9.net/dns-query")
        #expect(dns.servers == ["dns.google", "dns.quad9.net"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/110")) func aTemplateWithoutAHostIsNamedButNotShown() {
        #expect(SecureDNS(mode: "secure", templates: "not a url/secret").line == "secure via a custom server")
    }

    // Settings ▸ Privacy ▸ Secure DNS (#133).

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133")) func eachRowWritesWhatChromeWrites() {
        #expect(SecureDNSPrefs(.automatic) == SecureDNSPrefs(mode: "automatic", templates: ""))
        #expect(SecureDNSPrefs(.off) == SecureDNSPrefs(mode: "off", templates: ""))
        let google = SecureDNSProvider.all[0]
        #expect(SecureDNSPrefs(.provider(google)) == SecureDNSPrefs(mode: "secure", templates: "https://dns.google/dns-query{?dns}"))
        #expect(SecureDNSPrefs(.custom, custom: " https://dns.nextdns.io/a1b2c3/MacBook ")
            == SecureDNSPrefs(mode: "secure", templates: "https://dns.nextdns.io/a1b2c3/MacBook"))
        #expect(SecureDNSPrefs(.custom, custom: "http://dns.example/dns-query") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133")) func whatChromiumHoldsShowsAsItsRow() {
        #expect(SecureDNSPrefs(mode: "", templates: "").choice == .automatic)
        #expect(SecureDNSPrefs(mode: "automatic", templates: "").choice == .automatic)
        #expect(SecureDNSPrefs(mode: "automatic", templates: "https://dns.google/dns-query{?dns}").choice == .automatic)
        #expect(SecureDNSPrefs(mode: "off", templates: "https://dns.google/dns-query{?dns}").choice == .off)
        guard case .provider(let quad9) = SecureDNSPrefs(mode: "secure", templates: "https://dns.quad9.net/dns-query\n").choice else {
            Issue.record("Quad9 not recognised"); return
        }
        #expect(quad9.name == "Quad9 (9.9.9.9)")
        #expect(SecureDNSPrefs(mode: "secure", templates: "https://dns.nextdns.io/a1b2c3").choice == .custom)
        #expect(SecureDNSPrefs(mode: "secure", templates: "").choice == .custom)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133")) func everyProviderRoundTrips() {
        for p in SecureDNSProvider.all {
            #expect(SecureDNSPrefs(.provider(p))?.choice == .provider(p))
            #expect(SecureDNSPrefs.validTemplates(p.template) == p.template)
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133"), arguments: [
        ("https://dns.google/dns-query{?dns}", "https://dns.google/dns-query{?dns}"),
        ("https://dns.nextdns.io/a1b2c3/My%20Mac", "https://dns.nextdns.io/a1b2c3/My%20Mac"),
        ("HTTPS://dns.example:8443/q", "HTTPS://dns.example:8443/q"),
        ("https://a.example/dns-query\n  https://b.example/dns-query{?dns}", "https://a.example/dns-query https://b.example/dns-query{?dns}"),
    ])
    func customTemplatesKeepTheirPath(text: String, templates: String) {
        #expect(SecureDNSPrefs.validTemplates(text) == templates)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133"), arguments: [
        "", "   ", "dns.google", "http://dns.google/dns-query", "tls://dns.google", "https://",
        "https:///dns-query", "https://user:pw@dns.example/q", "https://dns.example/q{?dns",
        "https://dns.example/q}", "https://dns.google/dns-query http://plain.example/q",
    ])
    func customTemplatesMustBeHTTPS(text: String) {
        #expect(SecureDNSPrefs.validTemplates(text) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133")) func summaryNamesTheServerInEffect() {
        #expect(SecureDNS(mode: "secure", templates: "https://dns.google/dns-query{?dns}").summary.contains("dns.google"))
        #expect(SecureDNS(mode: "automatic", templates: "").summary.hasPrefix("Automatic uses the network’s own resolver"))
        #expect(SecureDNS(mode: "off", templates: "").summary.contains("plain text"))
        #expect(SecureDNS(mode: "secure", templates: "").summary.contains("No provider"))
        #expect(!SecureDNS(mode: "secure", templates: "https://dns.nextdns.io/a1b2c3").summary.contains("a1b2c3"))
        #expect(SecureDNS(mode: "", templates: "").summary.isEmpty)
    }
}
