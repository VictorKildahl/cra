import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ "Always keep these sites active" (GitHub #458): Arc's and Chrome's list, which
/// sites it covers and how it goes into Chrome's own pref.
struct KeepActiveSitesTests {
    /// The issue's own boundaries: example.com with its subdomains covers app.example.com, never
    /// notexample.com or example.com.other.test; that address only covers itself.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func subdomainBoundaries() {
        let site = KeepActiveSite(host: "example.com")
        #expect(site.matches(url: "https://example.com/inbox"))
        #expect(site.matches(url: "https://app.example.com/dashboard"))
        #expect(site.matches(url: "http://a.b.example.com:8080/"))
        #expect(site.matches(url: "https://EXAMPLE.com./"))
        #expect(!site.matches(url: "https://notexample.com/"))
        #expect(!site.matches(url: "https://example.com.other.test/"))
        #expect(!site.matches(url: "https://example.co/"))
        let only = KeepActiveSite(host: "example.com", includesSubdomains: false)
        #expect(only.matches(url: "https://example.com/"))
        #expect(!only.matches(url: "https://app.example.com/"))
        #expect(!only.matches(url: "https://www.example.com/"))
    }

    /// Pages with no host, and IP addresses, which have no subdomains.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func hostlessPagesAndAddresses() {
        #expect(!KeepActiveSite(host: "example.com").matches(url: "file:///Users/me/example.com"))
        #expect(!KeepActiveSite(host: "example.com").matches(url: "about:blank"))
        #expect(!KeepActiveSite(host: "0.0.1").matches(url: "http://127.0.0.1/"))
        #expect(KeepActiveSite(host: "127.0.0.1").matches(url: "http://127.0.0.1:3000/"))
        #expect(KeepActiveSite(host: "localhost").matches(url: "http://localhost:5173/"))
    }

    /// What can be typed: an address, a URL, Chrome's `.host` (that address only) and `*.host`.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func typedForms() throws {
        #expect(KeepActiveSite.parse("  Mail.Example.com ")?.host == "mail.example.com")
        #expect(KeepActiveSite.parse("https://app.example.com:8443/inbox?x=1")?.host == "app.example.com")
        #expect(KeepActiveSite.parse(".example.com")?.host == "example.com" && KeepActiveSite.parse(".example.com")?.includesSubdomains == false)
        #expect(KeepActiveSite.parse("*.example.com")?.includesSubdomains == true)
        #expect(KeepActiveSite.parse("[*.]example.com")?.host == "example.com" && KeepActiveSite.parse("[*.]example.com")?.includesSubdomains == true)
        #expect(KeepActiveSite.parse("example.com")?.includesSubdomains == nil)
        for bad in ["", "   ", "*", "exa mple.com", "https://", "."] { #expect(KeepActiveSite.parse(bad) == nil, "\(bad)") }
        // A typed scope wins over the switch until the list is tidied.
        #expect(!KeepActiveSite(host: ".example.com", includesSubdomains: true).matches(url: "https://app.example.com/"))
        #expect(KeepActiveSite(host: "*.example.com", includesSubdomains: false).matches(url: "https://app.example.com/"))
    }

    /// Adding skips an address that names nothing and one already listed with the same scope.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func addAndTidy() {
        var s = AppSettings()
        #expect(s.keepActiveSites.isEmpty && !s.keepsActive(url: "https://example.com/"))
        let first = s.addKeepActiveSite("https://example.com/inbox")
        let again = s.addKeepActiveSite("example.com")
        let only = s.addKeepActiveSite(".example.com")
        let none = s.addKeepActiveSite("not a host")
        #expect(first?.host == "example.com" && again == nil && only?.includesSubdomains == false && none == nil)
        #expect(s.keepsActive(url: "https://app.example.com/") && !s.keepsActive(url: "https://other.test/"))
        s.keepActiveSites += [KeepActiveSite(host: "  "), KeepActiveSite(host: "*.Mail.test/x"), KeepActiveSite(host: "mail.test")]
        s.tidyKeepActiveSites()
        #expect(s.keepActiveSites.map(\.host) == ["example.com", "example.com", "mail.test"])
        #expect(s.keepActiveSites.map(\.includesSubdomains) == [true, false, true])
        // Removing the entry takes the site off.
        s.keepActiveSites.removeAll { $0.host == "mail.test" }
        #expect(!s.keepsActive(url: "https://mail.test/"))
    }

    /// settings.json without the key is every Cra before #458: an empty list. One entry written
    /// by hand with only its host still loads, with its subdomains.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func loadsAndSaves() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).keepActiveSites == [])
        let json = #"{"keepActiveSites": [{"host": "example.com"}, {"host": "mail.test", "includesSubdomains": false}]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.keepActiveSites.map(\.host) == ["example.com", "mail.test"] && s.keepActiveSites.map(\.includesSubdomains) == [true, false])
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(again == s)
    }

    /// Chrome's pref: `example.com` with subdomains, `.example.com` that address only, an address
    /// as itself, each with the time it was added (microseconds since 1601, as a string). An
    /// unchanged list writes nothing; a pattern already there keeps its time.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func chromePref() throws {
        var s = AppSettings()
        s.keepActiveSites = [KeepActiveSite(host: "example.com"), KeepActiveSite(host: "mail.test", includesSubdomains: false),
                             KeepActiveSite(host: "127.0.0.1", includesSubdomains: false), KeepActiveSite(host: "")]
        #expect(s.keepActiveSites.map(\.chromePattern) == ["example.com", ".mail.test", "127.0.0.1", nil])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let written = try #require(s.chromeDiscardExceptions(current: ["example.com": "1"], now: now))
        #expect(written == ["example.com": "1", ".mail.test": "13444473600000000", "127.0.0.1": "13444473600000000"])
        #expect(s.chromeDiscardExceptions(current: written, now: now) == nil)
        #expect(AppSettings().chromeDiscardExceptions(current: [:], now: now) == nil)
        #expect(AppSettings().chromeDiscardExceptions(current: ["old.test": "1"], now: now) == [:])
    }

    /// An edit on chrome://settings/performance since Cra last wrote the list joins Cra's list:
    /// sites added there are added, sites removed there are removed.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458")) func chromePageEdits() {
        var s = AppSettings()
        s.addKeepActiveSite("example.com")
        s.addKeepActiveSite("mail.test", includesSubdomains: false)
        let last: Set<String> = ["example.com", ".mail.test"]
        let unchanged = s.adoptChromeEdits(current: last, lastWritten: last)
        let changed = s.adoptChromeEdits(current: ["example.com", "[*.]chat.test", ".docs.test"], lastWritten: last)
        #expect(!unchanged && changed)
        #expect(s.keepActiveSites.map(\.host) == ["example.com", "docs.test", "chat.test"])
        #expect(s.keepActiveSites.map(\.includesSubdomains) == [true, false, true])
        #expect(!s.keepsActive(url: "https://mail.test/"))
    }
}
