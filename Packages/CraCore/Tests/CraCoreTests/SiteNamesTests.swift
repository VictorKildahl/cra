import CraCore
import Foundation
import Testing

/// GitHub #91: "Hide site names" leaves no host of the session in any file of the zip.
struct SiteNamesTests {
    /// Lines as Cra and Chromium write them (cra.log, chromium.log, pages.txt), after the redaction.
    static let files = [
        "2026-11-02 10:00:01.000 tab 1A2B3C4D shown: mail.example.com, loading\n2026-11-02 10:00:02.000 tab 1A2B3C4D loaded www.news.example.org (HTTP 200)",
        "[1102/100003.000:WARNING:CraCEF.mm(1173)] Cra: loading intranet failed: net::ERR_NAME_NOT_RESOLVED (-105)\nCra: renderer for 192.168.1.20 ended: crashed (code 11, )",
        "  on screen 1A2B3C4D: sidebar mail.example.com, page mail.example.com, loading=false\n  probe: https://unknown.example.net/… blank=0",
        "tab sleep keeps NEWS.EXAMPLE.ORG awake: typed",
    ]

    @Test func everyHostOfTheSessionBecomesASiteNumber() {
        var names = SiteNames(hosts: ["mail.example.com", "news.example.org", "intranet", "192.168.1.20"])
        let out = Self.files.map { names.apply($0) }.joined(separator: "\n")
        for host in ["mail.example.com", "news.example.org", "NEWS.EXAMPLE.ORG", "intranet", "192.168.1.20", "unknown.example.net"] {
            #expect(!out.contains(host), "\(host) left in the export")
        }
        #expect(out.contains("shown: site-1, loading"))
        #expect(out.contains("loaded site-2 (HTTP 200)"))
        #expect(out.contains("sidebar site-1, page site-1"))
        #expect(out.contains("https://site-5/…"))
        #expect(out.contains("keeps site-2 awake"))
        // What isn't a host stays: file names, versions, error names.
        #expect(out.contains("CraCEF.mm(1173)"))
        #expect(out.contains("net::ERR_NAME_NOT_RESOLVED"))
    }

    @Test func theSameSiteKeepsItsNameAcrossFiles() {
        var names = SiteNames(hosts: ["example.com"])
        #expect(names.apply("a example.com") == "a site-1")
        #expect(names.apply("b www.example.com.") == "b site-1.")
        #expect(names.alias("other.com") == "site-2")
        #expect(names.alias("EXAMPLE.com") == "site-1")
        #expect(names.alias("(no page)") == "(no page)")
    }

    @Test func aDifferentSiteThatContainsAKnownOneIsNotTouchedUnlessItIsAnAddress() {
        var names = SiteNames(hosts: ["example.com"])
        #expect(names.apply("api.example.com and example.community") == "api.example.com and example.community")
        #expect(names.apply("see http://api.example.com:8080/x") == "see http://site-1:8080/x")
        #expect(names.apply("chrome-extension://abcdef/options.html") == "chrome-extension://abcdef/options.html")
        #expect(names.apply("--flag-name-.") == "--flag-name-.")
    }

    @Test func unicodeAndPunctuationPassThrough() {
        var names = SiteNames(hosts: ["example.com"])
        #expect(names.apply("“example.com” — ✓") == "“site-1” — ✓")
        #expect(names.apply("") == "")
    }

    @Test(arguments: [("https://www.Example.com/a", "www.Example.com"), ("wss://x.example.com", "x.example.com"),
                      ("chrome://settings", nil), ("cra://newtab", nil), ("file:///Users/a", nil), ("data:text/html,x", nil),
                      ("not a url", nil)] as [(String, String?)])
    func onlyWebAddressesNameASite(url: String, host: String?) {
        #expect(SiteNames.siteHost(of: url) == host)
    }

    @Test func keysIgnoreCaseWwwAndTheTrailingDot() {
        #expect(SiteNames.key("WWW.Example.COM.") == "example.com")
        #expect(SiteNames.key("(incognito)") == nil)
        #expect(SiteNames.key("") == nil)
    }
}
