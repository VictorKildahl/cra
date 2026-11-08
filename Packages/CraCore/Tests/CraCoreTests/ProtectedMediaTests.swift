import CraCore
import Foundation
import Testing

/// Which engine a page gets: WebKit (FairPlay) for the DRM services, Chromium for the rest.
struct ProtectedMediaTests {
    let sites = ProtectedMediaSites()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/66"), arguments: [
        "https://open.spotify.com/",
        "https://open.spotify.com/track/1?si=x",
        "https://www.netflix.com/browse",
        "https://NETFLIX.com/title/1",
        "https://www.disneyplus.com/",
        "https://play.max.com/",
        "https://www.hbomax.com/",
        "https://auth.max.com/login",
        "https://www.primevideo.com/",
        "https://tv.apple.com/",
        "https://music.apple.com/us/browse",
        "https://listen.tidal.com/",
        "https://www.crunchyroll.com/watch/x",
        "https://www.hotstar.com/in",
        "https://www.jiohotstar.com/",
        "https://v.qq.com/x/cover/x.html",
        "https://www.joyn.de/filme/x",
        "https://www.rakuten.tv/dk",
        "https://www.skyshowtime.com/watch",
        "https://www.nowtv.com/watch/home",
        "https://www.wowtv.de/",
        "https://www.showmax.com/",
        "http://www.hulu.com/",
        "https://www.netflix.com./browse",
    ])
    func servicesOpenInWebKit(url: String) {
        #expect(sites.engine(for: url) == .webKit)
    }

    @Test(arguments: [
        "https://www.google.com/search?q=spotify.com",
        "https://example.com/?u=https://open.spotify.com/",
        "https://notspotify.com/",
        "https://spotify.com.evil.example/",
        "https://www.apple.com/",
        "https://support.apple.com/",
        "https://appleid.apple.com/auth/authorize",
        "https://accounts.spotify.com/authorize?client_id=x",
        "https://www.spotify.com/us/premium/",
        "https://login.tidal.com/authorize",
        "https://connect.deezer.com/oauth/auth.php",
        "https://www.youtube.com/watch?v=x",
        "https://qq.com/",
        "https://mail.qq.com/",
        "about:blank",
        "chrome://settings",
        "view-source:https://open.spotify.com/",
        "file:///Users/x/spotify.com.html",
        "data:text/html,netflix.com",
        "",
        "netflix.com",
    ])
    func everythingElseStaysInChromium(url: String) {
        #expect(sites.engine(for: url) == .chromium)
    }

    /// The name the toast and the Site Control Center use.
    @Test func serviceNames() {
        #expect(sites.serviceName(for: "https://open.spotify.com/track/1") == "Spotify")
        #expect(sites.serviceName(for: "https://www.netflix.com/browse") == "Netflix")
        #expect(sites.serviceName(for: "https://www.disneyplus.com/") == "Disney+")
        #expect(sites.serviceName(for: "https://play.hbomax.com/") == "HBO Max")
        #expect(sites.serviceName(for: "https://music.apple.com/us/browse") == "Apple Music")
        #expect(sites.serviceName(for: "https://www.crunchyroll.com/") == "Crunchyroll")
        #expect(sites.serviceName(for: "https://v.qq.com/") == "Tencent Video")
        #expect(sites.serviceName(for: "https://www.google.com/") == nil)
        #expect(ProtectedMediaSites(extraHosts: ["stream.example.org"]).serviceName(for: "https://stream.example.org/") == "stream.example.org")
        #expect(ProtectedMediaSites(isEnabled: false).serviceName(for: "https://open.spotify.com/") == nil)
        // Every listed service has a name.
        #expect(ProtectedMediaSites.defaultHosts.allSatisfy { ProtectedMediaSites.serviceNames[$0] != nil })
    }

    /// Prime Video where Amazon serves it, and Amazon Music; the rest of Amazon stays in Chromium.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/66")) func amazon() {
        #expect(sites.engine(for: "https://www.amazon.com/gp/video/detail/B0X/ref=x?autoplay=1") == .webKit)
        #expect(sites.engine(for: "https://www.amazon.com/gp/video") == .webKit)
        #expect(sites.engine(for: "https://www.amazon.co.uk/gp/video/storefront") == .webKit)
        #expect(sites.engine(for: "https://music.amazon.com/albums/x") == .webKit)
        #expect(sites.engine(for: "https://music.amazon.de/") == .webKit)
        #expect(sites.engine(for: "https://www.amazon.com/") == .chromium)
        #expect(sites.engine(for: "https://www.amazon.com/dp/B0X") == .chromium)
        #expect(sites.engine(for: "https://www.amazon.com/gp/videogames") == .chromium)
        #expect(sites.engine(for: "https://www.amazon.com/ap/signin?openid.return_to=x") == .chromium)
        #expect(sites.engine(for: "https://www.amazon.dk/gp/video") == .chromium)
        #expect(sites.serviceName(for: "https://www.amazon.com/gp/video/detail/1") == "Prime Video")
        #expect(sites.serviceName(for: "https://music.amazon.co.uk/") == "Amazon Music")
        // A Chromium page going to Prime Video moves; Amazon's shopping pages don't.
        #expect(sites.handoff(from: .chromium, to: "https://www.amazon.com/gp/video/detail/1", method: "GET") == .webKit)
        #expect(sites.handoff(from: .chromium, to: "https://www.amazon.com/s?k=tv", method: "GET") == nil)
    }

    /// The Site Control Center's Safari's Engine switch: what Cra keeps after a choice.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/66")) func choosingPerSite() {
        // A site off the list goes to WebKit, and back.
        var r = ProtectedMediaSites.choosing(.webKit, for: "https://www.viaplay.dk/film", added: [], removed: [])
        #expect(r.added == ["www.viaplay.dk"] && r.removed.isEmpty)
        #expect(ProtectedMediaSites(extraHosts: r.added).engine(for: "https://www.viaplay.dk/serier") == .webKit)
        r = ProtectedMediaSites.choosing(.chromium, for: "https://www.viaplay.dk/film", added: r.added, removed: r.removed)
        #expect(r.added.isEmpty && r.removed.isEmpty)
        // A listed one taken off goes under the entry it falls under, and comes back.
        r = ProtectedMediaSites.choosing(.chromium, for: "https://www.netflix.com/browse", added: [], removed: [])
        #expect(r.added.isEmpty && r.removed == ["netflix.com"])
        #expect(ProtectedMediaSites(removedHosts: r.removed).engine(for: "https://www.netflix.com/title/1") == .chromium)
        r = ProtectedMediaSites.choosing(.webKit, for: "https://www.netflix.com/browse", added: r.added, removed: r.removed)
        #expect(r.added.isEmpty && r.removed.isEmpty)
        // Path entries too.
        r = ProtectedMediaSites.choosing(.chromium, for: "https://www.amazon.com/gp/video/detail/1", added: [], removed: [])
        #expect(r.removed == ["amazon.com/gp/video"])
        #expect(ProtectedMediaSites(removedHosts: r.removed).engine(for: "https://www.amazon.com/gp/video") == .chromium)
        // Choosing what already holds changes nothing; a non-web address changes nothing.
        r = ProtectedMediaSites.choosing(.webKit, for: "https://open.spotify.com/", added: [], removed: [])
        #expect(r.added.isEmpty && r.removed.isEmpty)
        r = ProtectedMediaSites.choosing(.webKit, for: "chrome://settings", added: ["a.com"], removed: ["b.com"])
        #expect(r.added == ["a.com"] && r.removed == ["b.com"])
    }

    @Test func offMeansChromiumEverywhere() {
        let off = ProtectedMediaSites(isEnabled: false)
        #expect(off.engine(for: "https://open.spotify.com/") == .chromium)
        #expect(off.handoff(from: .chromium, to: "https://open.spotify.com/", method: "GET") == nil)
    }

    @Test func listCanGrowAndShrink() {
        let custom = ProtectedMediaSites(extraHosts: [" 127.0.0.1 ", "https://Stream.Example.org/path", ".videos.example.net."],
                                         removedHosts: ["NETFLIX.com"])
        #expect(custom.engine(for: "http://127.0.0.1:8123/page.html") == .webKit)
        #expect(custom.engine(for: "https://stream.example.org/") == .webKit)
        #expect(custom.engine(for: "https://example.org/") == .chromium)
        #expect(custom.engine(for: "https://www.videos.example.net/") == .webKit)
        #expect(custom.engine(for: "https://www.netflix.com/") == .chromium)
        #expect(custom.engine(for: "https://open.spotify.com/") == .webKit)
        #expect(custom.engine(for: "https://open.spotify.com.") == .webKit)
    }

    @Test func entriesAreCleanedAndDeduplicated() {
        let custom = ProtectedMediaSites(extraHosts: ["open.spotify.com", "OPEN.SPOTIFY.COM", "", "  ", "a b", "x.com/a b", "x.com/?q"])
        #expect(custom.hosts.filter { $0 == "open.spotify.com" }.count == 1)
        #expect(custom.hosts.count == ProtectedMediaSites.defaultHosts.count)
        #expect(ProtectedMediaSites(extraHosts: ["X.com/Watch/"]).hosts.last == "x.com/watch")
    }

    /// A Chromium page's own navigation to a service moves before the request goes out; a POST
    /// can't move its body, and a WebKit page never leaves by itself (sign-in round trips).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/66")) func handoffRules() {
        #expect(sites.handoff(from: .chromium, to: "https://www.netflix.com/browse", method: "GET") == .webKit)
        #expect(sites.handoff(from: .chromium, to: "https://www.netflix.com/browse", method: "get") == .webKit)
        #expect(sites.handoff(from: .chromium, to: "https://open.spotify.com/callback", method: "POST") == nil)
        // Another site's "Sign in with Spotify" finishes where it started.
        #expect(sites.handoff(from: .chromium, to: "https://accounts.spotify.com/authorize?client_id=x", method: "GET") == nil)
        #expect(sites.handoff(from: .chromium, to: "https://www.google.com/", method: "GET") == nil)
        #expect(sites.handoff(from: .webKit, to: "https://accounts.google.com/o/oauth2", method: "GET") == nil)
        #expect(sites.handoff(from: .webKit, to: "https://open.spotify.com/", method: "GET") == nil)
    }
}
