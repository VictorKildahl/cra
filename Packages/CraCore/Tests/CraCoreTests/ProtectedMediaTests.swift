import CraCore
import Foundation
import Testing

/// Which engine a page gets: WebKit (FairPlay) for the DRM services, Chromium for the rest.
struct ProtectedMediaTests {
    let sites = ProtectedMediaSites()

    @Test(arguments: [
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
        #expect(sites.serviceName(for: "https://www.google.com/") == nil)
        #expect(ProtectedMediaSites(extraHosts: ["crunchyroll.com"]).serviceName(for: "https://www.crunchyroll.com/") == "crunchyroll.com")
        #expect(ProtectedMediaSites(isEnabled: false).serviceName(for: "https://open.spotify.com/") == nil)
        // Every listed service has a name.
        #expect(ProtectedMediaSites.defaultHosts.allSatisfy { ProtectedMediaSites.serviceNames[$0] != nil })
    }

    @Test func offMeansChromiumEverywhere() {
        let off = ProtectedMediaSites(isEnabled: false)
        #expect(off.engine(for: "https://open.spotify.com/") == .chromium)
        #expect(off.handoff(from: .chromium, to: "https://open.spotify.com/", method: "GET") == nil)
    }

    @Test func listCanGrowAndShrink() {
        let custom = ProtectedMediaSites(extraHosts: [" 127.0.0.1 ", "https://Stream.Example.org/path", ".crunchyroll.com."],
                                         removedHosts: ["NETFLIX.com"])
        #expect(custom.engine(for: "http://127.0.0.1:8123/page.html") == .webKit)
        #expect(custom.engine(for: "https://stream.example.org/") == .webKit)
        #expect(custom.engine(for: "https://example.org/") == .chromium)
        #expect(custom.engine(for: "https://www.crunchyroll.com/") == .webKit)
        #expect(custom.engine(for: "https://www.netflix.com/") == .chromium)
        #expect(custom.engine(for: "https://open.spotify.com/") == .webKit)
        #expect(custom.engine(for: "https://open.spotify.com.") == .webKit)
    }

    @Test func entriesAreCleanedAndDeduplicated() {
        let custom = ProtectedMediaSites(extraHosts: ["open.spotify.com", "OPEN.SPOTIFY.COM", "", "  ", "a b", "x.com/path"])
        #expect(custom.hosts.filter { $0 == "open.spotify.com" }.count == 1)
        #expect(custom.hosts.count == ProtectedMediaSites.defaultHosts.count)
    }

    /// A Chromium page's own navigation to a service moves before the request goes out; a POST
    /// can't move its body, and a WebKit page never leaves by itself (sign-in round trips).
    @Test func handoffRules() {
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
