import CraCore
import Foundation
import Testing

/// A space's own search engine (GitHub #306): typed text in a space with one searches it, a space
/// without one searches the profile's default.
struct SpaceSearchEngineTests {
    typealias E = SiteSearchTests
    static let bing = ChromiumSearchEngine(id: 7, name: "Microsoft Bing", keyword: "bing.com", url: "https://www.bing.com/search?q={searchTerms}",
                                           prepopulateID: 3, safeForAutoreplace: true, isActive: 0)
    /// The profile's keywords table, as SiteSearchTests has it.
    static let rows = [E.google, E.yahoo, bing, E.duck, E.autoYouTube, E.history, E.wiki]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/306"))
    func aSpaceSearchesItsOwnEngine() {
        let engine = ChromiumSearchEngine.forSpace(keyword: "duckduckgo.com", default: E.google, among: Self.rows)
        #expect(engine == E.duck)
        #expect(engine.searchURL("cra browser") == "https://duckduckgo.com/?q=cra%20browser")
        // Keywords are matched without case, as Chromium's are.
        #expect(ChromiumSearchEngine.forSpace(keyword: "DK.Yahoo.com", default: E.google, among: Self.rows) == E.yahoo)
        // An engine the user added on the settings page counts too.
        #expect(ChromiumSearchEngine.forSpace(keyword: "wda", default: E.google, among: Self.rows) == E.wiki)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/306"))
    func withoutOneTheSpaceInheritsTheDefault() {
        #expect(ChromiumSearchEngine.forSpace(keyword: nil, default: Self.bing, among: Self.rows) == Self.bing)
        #expect(ChromiumSearchEngine.forSpace(keyword: "", default: Self.bing, among: Self.rows) == Self.bing)
        // An engine since removed from the profile, or never in it, falls back to the default…
        #expect(ChromiumSearchEngine.forSpace(keyword: "gone.example", default: Self.bing, among: Self.rows) == Self.bing)
        // …and the starter pack is no search engine.
        #expect(ChromiumSearchEngine.forSpace(keyword: "@history", default: Self.bing, among: Self.rows) == Self.bing)
    }

    @Test func beforeWebDataLoadsCrasOwnListStandsIn() {
        // A profile that hasn't loaded yet has no rows; Cra's own engines still resolve.
        let kagi = ChromiumSearchEngine.forSpace(keyword: "kagi.com", default: E.google, among: [])
        #expect(kagi.searchURL("x") == "https://kagi.com/search?q=x")
        #expect(ChromiumSearchEngine.spaceChoices(among: []).map(\.keyword) == ["google.com", "duckduckgo.com", "bing.com", "kagi.com"])
    }

    @Test func theMenuOffersBuiltInAndAddedEnginesOnly() {
        #expect(ChromiumSearchEngine.spaceChoices(among: Self.rows).map(\.keyword)
                == ["google.com", "dk.yahoo.com", "bing.com", "duckduckgo.com", "wda"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/306"))
    func theEngineIsSavedWithTheSpace() throws {
        let doc = SidebarDocument.fresh()
        var space = try #require(doc.spaces.first)
        #expect(space.searchEngine == nil)
        space.searchEngine = "duckduckgo.com"
        let data = try JSONEncoder().encode(space)
        #expect(try JSONDecoder().decode(Space.self, from: data).searchEngine == "duckduckgo.com")
        // A space saved before #306 has no key and inherits; one without an engine writes none,
        // so its file stays as older Cra wrote it.
        space.searchEngine = nil
        let plain = try JSONEncoder().encode(space)
        #expect(!String(decoding: plain, as: UTF8.self).contains("searchEngine"))
        #expect(try JSONDecoder().decode(Space.self, from: plain).searchEngine == nil)
    }
}
