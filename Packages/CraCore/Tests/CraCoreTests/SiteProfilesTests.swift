import CraCore
import Foundation
import Testing

/// Arc's domainToProfilePreferences, as observed in Arc 1.173.1 (docs/arc-reverse-engineering.md).
struct SiteProfilesTests {
    let work = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
    let personal = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!

    func space(_ n: Int, profile: UUID?) -> Space {
        Space(id: UUID(uuidString: "A0000000-0000-0000-0000-00000000000\(n)")!, title: "S\(n)", emoji: "", theme: .incognito,
              favoritesContainerID: UUID(), pinnedContainerID: UUID(), todayContainerID: UUID(),
              createdAt: Date(timeIntervalSince1970: 0), profileID: profile)
    }

    /// Nothing picked for a site yet: no profile of its own, and the Little Window follows the window used last.
    @Test func aSiteNobodyPickedAProfileForHasNone() {
        #expect(SiteProfiles().profile(for: "https://gitlab.example.com/a") == nil)
    }

    /// A profile picked in a Little Window is the site's from then on, Default included, and a later
    /// pick replaces it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/768")) func thePickIsRememberedForTheSiteAndReplacedByTheNext() {
        var sites = SiteProfiles()
        sites.remember(work, for: "https://gitlab.example.com/a?b=1")
        #expect(sites.profile(for: "https://gitlab.example.com/other") == RememberedProfile(id: work))
        sites.remember(nil, for: "https://gitlab.example.com/a")
        #expect(sites.profile(for: "https://gitlab.example.com/") == RememberedProfile(id: nil))
    }

    /// The key is the host without a leading www. and without case: www.example.net is example.net, a
    /// subdomain is a site of its own.
    @Test func theSiteIsTheHostWithoutWWW() {
        var sites = SiteProfiles()
        sites.remember(personal, for: "https://Example.net/x")
        #expect(sites.profile(for: "https://www.example.net/") == RememberedProfile(id: personal))
        #expect(sites.profile(for: "https://sub.example.net/") == nil)
        #expect(SiteProfiles.site(of: "about:blank") == nil)
        #expect(SiteProfiles.site(of: "file:///tmp/a.html") == nil)
    }

    /// A Little Window on the site opens in the first space in the sidebar on its profile, whichever
    /// window was used last.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/768")) func theSiteOpensInTheFirstSpaceOnItsProfile() {
        var sites = SiteProfiles()
        let spaces = [space(1, profile: personal), space(2, profile: nil), space(3, profile: nil)]
        sites.remember(nil, for: "https://gitlab.example.com/")
        #expect(sites.space(for: "https://gitlab.example.com/x", lastUsed: spaces[0].id, in: spaces) == spaces[1].id)
        sites.remember(personal, for: "https://youtube.com/")
        #expect(sites.space(for: "https://www.youtube.com/watch", lastUsed: spaces[2].id, in: spaces) == spaces[0].id)
    }

    /// The window used last decides when it is on the site's profile already, when the site has no
    /// profile, and when no space uses it any more (a profile deleted since).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/768")) func theWindowUsedLastKeepsTheSiteWhenItCan() {
        var sites = SiteProfiles()
        let spaces = [space(1, profile: personal), space(2, profile: nil), space(3, profile: nil)]
        sites.remember(nil, for: "https://gitlab.example.com/")
        #expect(sites.space(for: "https://gitlab.example.com/x", lastUsed: spaces[2].id, in: spaces) == nil)
        sites.remember(work, for: "https://gone.example.com/")
        #expect(sites.space(for: "https://gone.example.com/", lastUsed: spaces[0].id, in: spaces) == nil)
        #expect(sites.space(for: "https://unknown.example.com/", lastUsed: spaces[0].id, in: spaces) == nil)
    }

    /// Arc's picks come over by site, and a pick already made in Cra stays.
    @Test func importedPicksDoNotReplaceCrasOwn() {
        var sites = SiteProfiles()
        sites.remember(personal, for: "https://youtube.com/")
        sites.adopt(["youtube.com": RememberedProfile(id: work), "WWW.gitlab.example.com": RememberedProfile(id: nil)])
        #expect(sites.profile(for: "https://youtube.com/") == RememberedProfile(id: personal))
        #expect(sites.profile(for: "https://gitlab.example.com/") == RememberedProfile(id: nil))
    }

    /// Saved as a plain object of site → profile ("default" for Default), as history keeps profiles.
    @Test func savedAsSiteToProfileKey() throws {
        var sites = SiteProfiles()
        sites.remember(nil, for: "https://a.example.com/")
        sites.remember(work, for: "https://b.example.com/")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sites)) as? [String: String])
        #expect(json == ["a.example.com": "default", "b.example.com": work.uuidString])
        #expect(try JSONDecoder().decode(SiteProfiles.self, from: JSONEncoder().encode(sites)) == sites)
    }
}
