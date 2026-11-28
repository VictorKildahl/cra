import CraCore
import Foundation
import Testing

/// Chromium's search engines in the command bar: its default searches what is typed, and its
/// keywords take Tab next to Arc's sites (reported on X, 2 Nov 2026).
struct SiteSearchTests {
    /// Rows as Chromium 156 keeps them in Web Data (Cra's own profile, 3 Nov 2026).
    static let google = ChromiumSearchEngine(
        id: 9, name: "Google", keyword: "google.com",
        url: "{google:baseURL}search?q={searchTerms}&{google:RLZ}{google:originalQueryForSuggestion}{google:assistedQueryStats}{google:searchFieldtrialParameter}{google:language}{google:prefetchSource}{google:searchClient}{google:sourceId}{google:searchSource}{google:contextualSearchVersion}ie={inputEncoding}",
        suggestURL: "{google:baseSuggestURL}{google:suggestPath}?{google:searchFieldtrialParameter}client={google:suggestClient}&gs_ri={google:suggestRid}&xssi=t&q={searchTerms}&{google:inputType}sugkey={google:suggestAPIKeyParameter}",
        prepopulateID: 1, safeForAutoreplace: true, isActive: 0, syncGUID: "485bf7d3-0215-45af-87dc-538868000001")
    static let yahoo = ChromiumSearchEngine(
        id: 5, name: "Yahoo Search", keyword: "dk.yahoo.com", url: "https://dk.search.yahoo.com/search{google:pathWildcard}?ei={inputEncoding}&p={searchTerms}",
        prepopulateID: 2, safeForAutoreplace: true, isActive: 0)
    static let duck = ChromiumSearchEngine(
        id: 6, name: "DuckDuckGo", keyword: "duckduckgo.com", url: "https://duckduckgo.com/?q={searchTerms}",
        suggestURL: "https://duckduckgo.com/ac/?q={searchTerms}&type=list", prepopulateID: 92, safeForAutoreplace: true, isActive: 0)
    /// Added by Chromium while browsing YouTube: inactive, so no Tab.
    static let autoYouTube = ChromiumSearchEngine(
        id: 16, name: "YouTube", keyword: "youtube.com", url: "https://www.youtube.com/results?search_query={searchTerms}&page={startPage?}&utm_source=opensearch",
        safeForAutoreplace: true, isActive: 0)
    static let history = ChromiumSearchEngine(id: 11, name: "History", keyword: "@history", url: "chrome://history/?q={searchTerms}",
                                              safeForAutoreplace: true, isActive: 1, starterPackID: 2)
    /// Added on the settings page.
    static let wiki = ChromiumSearchEngine(id: 30, name: "Wikipedia DA", keyword: "wda", url: "https://da.wikipedia.org/w/index.php?search={searchTerms}")

    @Test func googleExpandsWithoutTheOmniboxState() {
        #expect(Self.google.searchURL("hello world") == "https://www.google.com/search?q=hello%20world&ie=UTF-8")
        // The plain endpoint, not the XSSI-guarded omnibox one.
        #expect(Self.google.suggestURL("a&b")?.absoluteString == "https://www.google.com/complete/search?client=chrome&ie=utf-8&oe=utf-8&q=a%26b")
    }

    @Test func otherTemplates() {
        #expect(Self.yahoo.searchURL("ø") == "https://dk.search.yahoo.com/search?ei=UTF-8&p=%C3%B8")
        #expect(Self.duck.suggestURL("c++")?.absoluteString == "https://duckduckgo.com/ac/?q=c%2B%2B&type=list")
        #expect(Self.autoYouTube.searchURL("lofi") == "https://www.youtube.com/results?search_query=lofi&utm_source=opensearch")
        #expect(ChromiumSearchEngine.expand("https://e.example/?q={searchTerms}&mkt={language}#top", query: "x", language: "da") == "https://e.example/?q=x&mkt=da#top")
        #expect(Self.wiki.suggestURL("x") == nil)
    }

    @Test func whichKeywordsTakeTab() {
        #expect(Self.google.takesTab && Self.duck.takesTab && Self.wiki.takesTab)
        #expect(!Self.autoYouTube.takesTab && !Self.history.takesTab)
        var activated = Self.autoYouTube
        activated.isActive = 1
        #expect(activated.takesTab)
        var deactivated = Self.wiki
        deactivated.isActive = 2
        #expect(!deactivated.takesTab)
    }

    /// Arc's "New ChatGPT Message" (⌥⌘G) is a cloud AI partner Cra leaves out (docs/arc-parity.md); a site search
    /// added on chrome://settings/searchEngines does the same from ⌘T: its shortcut, Tab, the message, Return opens
    /// ChatGPT with it. What the reply on #828 tells people to set up.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/828"))
    func anAddedChatSiteSearchTakesTabAndCarriesTheMessage() {
        let chatGPT = ChromiumSearchEngine(id: 31, name: "ChatGPT", keyword: "gpt", url: "https://chatgpt.com/?q={searchTerms}")
        #expect(chatGPT.takesTab)
        let scope = SiteSearch.match("gpt", completion: "github.com", keywords: [Self.google, chatGPT])
        #expect(scope?.name == "ChatGPT")
        #expect(scope?.searchURL("Plan a trip to Rome & Florence?") == "https://chatgpt.com/?q=Plan%20a%20trip%20to%20Rome%20%26%20Florence%3F")
    }

    /// #854's own list, added on Chromium's page (Settings ▸ Profiles ▸ Search Settings…, which stores `%s` as
    /// `{searchTerms}`): each short keyword scopes the bar to its engine, a one-letter one included, and the search
    /// goes to its URL. Arc takes Tab only (its space trigger is off, docs/arc-reverse-engineering.md), so a
    /// keyword with a space after it is a search of the words, not a scope. An added engine made the default
    /// searches what's typed, as Brave Search does here.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/854"))
    func addedEnginesTakeTheirKeywordsAndCanBeTheDefault() {
        let github = ChromiumSearchEngine(id: 40, name: "GitHub", keyword: "gh", url: "https://github.com/search?q={searchTerms}")
        let youtube = ChromiumSearchEngine(id: 41, name: "YouTube", keyword: "yt", url: "https://www.youtube.com/results?search_query={searchTerms}")
        let wikipedia = ChromiumSearchEngine(id: 42, name: "Wikipedia", keyword: "w", url: "https://en.wikipedia.org/w/index.php?search={searchTerms}")
        let brave = ChromiumSearchEngine(id: 43, name: "Brave Search", keyword: "br", url: "https://search.brave.com/search?q={searchTerms}")
        let added = [Self.google, github, youtube, wikipedia, brave]
        #expect(added.allSatisfy { $0.takesTab })

        let gh = SiteSearch.match("gh", completion: "github.com", keywords: added)
        #expect(gh?.name == "GitHub")
        #expect(gh?.searchURL("swift testing") == "https://github.com/search?q=swift%20testing")
        #expect(gh?.color == "#743FC7")   // GitHub's pill, as Arc keys it on the URL
        #expect(SiteSearch.match("yt", completion: nil, keywords: added)?.searchURL("lofi") == "https://www.youtube.com/results?search_query=lofi")
        #expect(SiteSearch.match("w", completion: nil, keywords: added)?.name == "Wikipedia")
        #expect(SiteSearch.match("br", completion: nil, keywords: added)?.name == "Brave Search")
        #expect(SiteSearch.match("GH", completion: nil, keywords: added)?.name == "GitHub")

        // Tab, not Space.
        #expect(SiteSearch.match("gh ", completion: nil, keywords: added) == nil)
        #expect(SiteSearch.match("gh swift", completion: nil, keywords: added) == nil)

        // Picked as the default on that page (Chromium's pref), the bar's plain search goes to it.
        let picked = ChromiumSearchEngine(templateURLData: brave.templateURLData)
        #expect(picked?.searchURL("privacy browser") == "https://search.brave.com/search?q=privacy%20browser")
    }

    @Test func keywordsAroundArcsSites() {
        let keywords = [Self.google, Self.duck, Self.autoYouTube, Self.history, Self.wiki]
        // Typed out in full: the keyword, before Arc's sites ("goo" for a Google edited to that).
        var edited = Self.google
        edited.keyword = "goo"
        edited.safeForAutoreplace = false
        #expect(SiteSearch.match("goo", completion: nil, keywords: [edited])?.name == "Google")
        #expect(SiteSearch.match("wda", completion: nil, keywords: keywords)?.url == Self.wiki.url)
        // Arc's sites first for what only starts a host; Chromium's next, from two letters on.
        #expect(SiteSearch.match("you", completion: nil, keywords: keywords)?.color == "#FF0000")
        #expect(SiteSearch.match("duck", completion: nil, keywords: keywords)?.name == "DuckDuckGo")
        let kagi = ChromiumSearchEngine(.kagi)
        #expect(SiteSearch.match("k", completion: nil, keywords: [kagi]) == nil)
        #expect(SiteSearch.match("ka", completion: nil, keywords: [kagi])?.name == "Kagi")
        #expect(SiteSearch.match("@hist", completion: nil, keywords: keywords) == nil)
        #expect(SiteSearch.match("duck", completion: nil, keywords: [])?.name == nil)
        #expect(SiteSearch(Self.wiki).searchURL("a b") == "https://da.wikipedia.org/w/index.php?search=a%20b")
    }

    @Test func shortcutsUseTheirSearchDestinationsColor() {
        var youtube = Self.autoYouTube
        youtube.isActive = 1
        youtube.keyword = "yt"
        let alias = SiteSearch.match("yt", completion: nil, keywords: [youtube])
        #expect(alias?.color == "#FF0000")
        #expect(alias?.searchURL("c++") == "https://www.youtube.com/results?search_query=c%2B%2B&utm_source=opensearch")
        #expect(SiteSearch.match("youtube.com", completion: nil, keywords: [youtube])?.color == alias?.color)
        #expect(SiteSearch(Self.wiki).color == "#FFA500")

        let spotify = ChromiumSearchEngine(name: "Spotify", keyword: "sp", url: "https://open.spotify.com/search/{searchTerms}")
        #expect(SiteSearch(spotify).color == "#1DB954")
        let unrelated = ChromiumSearchEngine(name: "YouTube", keyword: "youtube.com", url: "https://notyoutube.com/?q={searchTerms}")
        #expect(SiteSearch(unrelated).color == nil)
        let proxied = ChromiumSearchEngine(name: "Other", keyword: "proxy", url: "https://example.com/?url=https://youtube.com&q={searchTerms}")
        #expect(SiteSearch(proxied).color == nil)
    }

    /// Arc's own list keeps its `%s` URLs.
    @Test func arcsSitesStillSearch() {
        #expect(SiteSearch.match("twit", completion: "twitch.tv")?.host == "twitter.com")
        #expect(SiteSearch.match("gm", completion: nil) == nil)
        #expect(SiteSearch.all.first { $0.name == "YouTube" }?.searchURL("a&b") == "https://www.youtube.com/results?search_query=a%26b")
    }

    /// The pref Chromium keeps the default in, read and written in its own keys.
    @Test func defaultEnginePref() throws {
        let mirrored: [String: Any] = ["id": "9", "short_name": "Google", "keyword": "google.com", "url": Self.google.url,
                                       "suggestions_url": Self.google.suggestURL, "prepopulate_id": 1, "safe_for_autoreplace": true,
                                       "is_active": 0, "starter_pack_id": 0, "synced_guid": Self.google.syncGUID]
        #expect(ChromiumSearchEngine(templateURLData: mirrored) == Self.google)
        #expect(ChromiumSearchEngine(templateURLData: [:]) == nil)
        let data = Self.duck.templateURLData
        #expect(data["synced_guid"] == nil && data["id"] as? String == "6" && data["prepopulate_id"] as? Int == 92)
        let json = try JSONSerialization.data(withJSONObject: data)
        let back = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(ChromiumSearchEngine(templateURLData: back) == Self.duck)
    }

    /// Cra's older engine setting moves to Chromium as its built-in row, or as an engine of its own.
    @Test func migratingCrasSetting() {
        let rows = [Self.google, Self.duck]
        #expect(ChromiumSearchEngine.migrating(.duckduckgo, among: rows) == Self.duck)
        #expect(ChromiumSearchEngine.migrating(.bing, among: rows).url == "https://www.bing.com/search?q={searchTerms}")
        let kagi = ChromiumSearchEngine.migrating(.kagi, among: rows)
        #expect(kagi.keyword == "kagi.com" && !kagi.isBuiltIn && kagi.searchURL("x") == "https://kagi.com/search?q=x")
        #expect(ChromiumSearchEngine(.google).searchURL("x") == "https://www.google.com/search?q=x&ie=UTF-8")
    }
}
