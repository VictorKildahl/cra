import Foundation
import Testing
@testable import CraCore

/// Arc Max's Instant Links (#407): Shift-Return on a search turns it into searches and opens the top
/// results. Arc's strings and Google selectors are from 1.172.2's binary; the rules on the model's
/// answer were measured on the Mac's on-device model.
struct InstantLinksTests {
    private typealias S = InstantLinks.Search
    private func s(_ q: String, _ n: Int = 1) -> S { S(query: q, count: n) }

    private func plan(_ phrase: String, _ format: InstantLinks.Format = .tab, _ searches: [S], title: String = "T") -> InstantLinks.Plan {
        InstantLinks.plan(title: title, format: format, searches: searches, phrase: phrase)
    }

    // MARK: Arc's text

    @Test func settingsAndRowTextsAreArcs() {
        #expect(InstantLinks.settingsTitle == "Instant Links")
        #expect(InstantLinks.settingsDetail == "Press Shift + Enter for any web search to instantly open the top result. You can also search multiple queries!")
        #expect(InstantLinks.searchingTitle == "Searching the web for you…")
        #expect(InstantLinks.errorTitle == "Oops, something went wrong.")
    }

    @Test func instructionsCarryTheRulesAndTheExamples() {
        let i = InstantLinks.instructions
        #expect(i.hasPrefix("You turn what someone typed into a browser's command bar into Google searches."))
        for example in [
            "\"the barbie trailer\" → tab \"Barbie Trailer\": [barbie trailer, 1]",
            "\"top 3 pizza places in naples\" → tab \"Pizza in Naples\": [best pizza naples, 3]",
            "\"folder of iphone chargers on amazon\" → folder \"iPhone Chargers\": [iphone chargers site:amazon.com, 1]",
            "\"ricette del tiramisù, apri le prime due\" → tab \"Ricette del Tiramisù\": [ricetta tiramisù, 2]",
        ] { #expect(i.contains(example)) }
        #expect(i.contains("like site:youtube.com."))
        #expect(i.contains("title: a short name for the results, in Title Case."))
    }

    // MARK: Rule 1, invented searches

    @Test func searchesTheModelInventedAreDropped() {
        // The model copied names from the examples: "youtube mkbhd" came back with mr beast and johnny harris.
        let p = plan("youtube mkbhd", .tab, [s("mkbhd site:youtube.com"), s("mr beast site:youtube.com"), s("johnny harris site:youtube.com")])
        #expect(p.searches == [s("mkbhd site:youtube.com")])
        // A site: token alone doesn't make a search the user's.
        #expect(plan("pizza", .tab, [s("barbie site:imdb.com"), s("pizza")]).searches == [s("pizza")])
    }

    @Test func aPlanWithNothingLeftSearchesThePhrase() {
        let p = plan("cheap flights to oslo", .tab, [s("barbie trailer")], title: "")
        #expect(p.searches == [s("cheap flights to oslo")])
        #expect(p.title == "Cheap Flights To Oslo")
        #expect(plan("x y", .tab, []).searches == [s("x y")])
    }

    // MARK: Rule 2, a named site becomes site:

    @Test func aNamedSiteBecomesASiteFilter() {
        // The model wrote the site's name into the query instead.
        #expect(plan("search reddit for oatmeal cookie recipes", .tab, [s("oatmeal cookie recipes reddit")]).searches
                == [s("oatmeal cookie recipes site:reddit.com")])
        #expect(plan("youtube linus tech tips", .tab, [s("youtube linus tech tips")]).searches == [s("linus tech tips site:youtube.com")])
        #expect(plan("iphone chargers on amazon", .tab, [s("iphone chargers amazon")]).searches == [s("iphone chargers site:amazon.com")])
        #expect(plan("twitter elon", .tab, [s("twitter elon")]).searches == [s("elon site:x.com")])
        #expect(plan("threads news", .tab, [s("threads news")]).searches == [s("news site:threads.net")])
        // Left alone: already filtered, or the name is the whole search.
        #expect(plan("youtube mkbhd", .tab, [s("mkbhd site:youtube.com")]).searches == [s("mkbhd site:youtube.com")])
        #expect(plan("youtube", .tab, [s("youtube")]).searches == [s("youtube")])
    }

    @Test func theFormatsWordsAreNotSearchedFor() {
        // Measured on the Mac's model, 13 Nov 2026: the folder's words stayed in the search.
        let p = plan("cartella con guide per sciare a tarvisio", .folder, [s("cartella con guide per sciare a tarvisio")])
        #expect(p.format == .folder)
        #expect(p.searches == [s("guide per sciare a tarvisio")])
        #expect(plan("split view of the swift docs and the kotlin docs", .split, [s("split view of the swift docs"), s("the kotlin docs")]).searches
                == [s("the swift docs"), s("the kotlin docs")])
        // Nothing but the format's words: the search stays as written.
        #expect(plan("folder of", .folder, [s("folder of")]).searches == [s("folder of")])
        let plain = InstantLinks.plainPlan(for: "folder of pizza")
        #expect(plain.format == .folder)
        #expect(plain.title == "Pizza")
        #expect(plain.searches == [s("pizza")])
    }

    @Test func aSiteThePhraseNamesAndTheModelDroppedIsSearchedOn() {
        // Measured on the Mac's model, 12 Nov 2026: both came back without the site.
        #expect(plan("search reddit for oatmeal cookie recipes", .tab, [s("oatmeal cookie recipes")]).searches
                == [s("oatmeal cookie recipes site:reddit.com")])
        #expect(plan("infatuation best italian restaurants in nyc", .tab, [s("best italian restaurants in nyc")]).searches
                == [s("best italian restaurants in nyc site:theinfatuation.com")])
        // Two sites named: the model has to say which search goes where.
        #expect(plan("mkbhd on youtube and reddit", .tab, [s("mkbhd")]).searches == [s("mkbhd")])
    }

    // MARK: Rule 3, duplicates

    @Test func theSameThingTwiceIsOneSearchWithTheLargerCount() {
        let p = plan("a few easy ramen recipes", .tab, [s("ramen recipes"), s("easy ramen recipes", 3)])
        #expect(p.searches == [s("ramen recipes", 3)])
        // Plural, stop words and "best" don't make two searches.
        #expect(plan("best pizza in naples", .tab, [s("pizza naples"), s("best pizzas in naples")]).searches == [s("pizza naples")])
        // Different sites are different searches.
        #expect(plan("mkbhd on youtube and reddit", .tab, [s("mkbhd site:youtube.com"), s("mkbhd site:reddit.com")]).searches.count == 2)
    }

    @Test func differentThingsAreNotMerged() {
        let two = [s("greek restaurants greenpoint"), s("italian restaurants greenpoint")]
        #expect(plan("greek and italian restaurants in greenpoint in a split", .split, two).searches == two)
        let trailer = [s("barbie trailer"), s("barbie showtimes")]
        #expect(plan("the barbie trailer and the showtimes", .tab, trailer).searches == trailer)
    }

    // MARK: Rule 4, counts

    @Test func aCountNeedsAWordInThePhraseToBackIt() {
        #expect(plan("pizza places in naples", .tab, [s("pizza naples", 5)]).searches == [s("pizza naples")])
        #expect(plan("top pizza places in naples", .tab, [s("pizza naples", 5)]).searches == [s("pizza naples", 5)])
        #expect(plan("a few lasagna recipes", .tab, [s("lasagna recipes", 3)]).searches == [s("lasagna recipes", 3)])
        #expect(plan("le prime due ricette", .tab, [s("ricette", 2)]).searches == [s("ricette", 2)])
        #expect(plan("pizza", .tab, [s("pizza", 0)]).searches == [s("pizza")])
        #expect(plan("top 99 pizza", .tab, [s("pizza", 99)]).searches == [s("pizza", 10)])
    }

    @Test func aSingleSearchTakesTheCountThePhraseStates() {
        // The model answered 1 for "top 10 ..." and 5 for "3 easy ...".
        #expect(plan("top 10 hiking trails in utah", .tab, [s("hiking trails utah", 1)]).searches == [s("hiking trails utah", 10)])
        #expect(plan("3 easy bread recipes", .tab, [s("easy bread recipes", 5)]).searches == [s("easy bread recipes", 3)])
        // Two searches keep the model's counts.
        let two = [s("barbie trailer", 2), s("barbie showtimes")]
        #expect(plan("2 barbie trailer and showtimes", .tab, two).searches == two)
    }

    @Test func statedCounts() {
        let table: [(String, Int?)] = [
            ("top 5 pizza places in naples", 5),
            ("top 10 hiking trails", 10),
            ("the first two episodes of severance", 2),
            ("first 3 results for solar panels", 3),
            ("a couple lasagna recipes", 2),
            ("a few lasagna recipes", 3),
            ("qualche ricetta di lasagne", 3),
            ("3 easy bread recipes", 3),
            ("show me 4 tutorials for swift", 4),
            ("give me three pasta recipes", 3),
            ("dammi 3 ristoranti a trieste", 3),
            ("ricette del tiramisù, apri le prime due", 2),
            ("le 4 migliori piste da sci", 4),
            ("i primi cinque film di kubrick", 5),
            ("5 best laptops", 5),
            ("ten best laptops", 10),
            // Numbers that belong to the thing itself.
            ("1984 by george orwell", nil),
            ("iphone 15 cases", nil),
            ("windows 11 download", nil),
            ("best 2 player board games", nil),
            ("2 player games", nil),
            ("top 11 movies", nil),
            ("pizza", nil),
            ("", nil),
        ]
        for (phrase, expected) in table {
            #expect(InstantLinks.statedCount(in: phrase) == expected, "\(phrase)")
        }
    }

    // MARK: Rule 6, format

    @Test func aSplitOrFolderNeedsAWordForIt() {
        let one = [s("pizza")]
        #expect(plan("pizza", .split, one).format == .tab)
        #expect(plan("pizza", .folder, one).format == .tab)
        #expect(plan("pizza in a split", .split, one).format == .split)
        #expect(plan("pizza and pasta side by side", .split, one).format == .split)
        #expect(plan("pizza e pasta affiancate", .split, one).format == .split)
        #expect(plan("pizza on the left and pasta on the right", .split, one).format == .split)
        #expect(plan("pizza a sinistra e pasta a destra", .split, one).format == .split)
        // Only one side is no split.
        #expect(plan("turn left at the pizza", .split, one).format == .tab)
        #expect(plan("pizza folder", .folder, one).format == .folder)
        #expect(plan("cartella pizza", .folder, one).format == .folder)
    }

    @Test func aTabBecomesAFolderOrSplitWhenTheWordsAskForIt() {
        let one = [s("iphone chargers site:amazon.com")]
        for phrase in ["folder of iphone chargers", "iphone chargers in a folder", "cartella con caricabatterie", "cartella di caricabatterie", "caricabatterie in una cartella"] {
            #expect(plan(phrase, .tab, one).format == .folder, "\(phrase)")
        }
        for phrase in ["iphone chargers in split view", "iphone chargers in a split", "iphone chargers split with cases", "split of iphone chargers", "iphone chargers in split"] {
            #expect(plan(phrase, .tab, one).format == .split, "\(phrase)")
        }
        #expect(plan("iphone chargers", .tab, one).format == .tab)
    }

    // MARK: What to open

    @Test func openingsFollowTheSearchesCounts() {
        #expect(InstantLinks.openings(for: plan("barbie trailer", .tab, [s("barbie trailer")])) == [s("barbie trailer")])
        #expect(InstantLinks.openings(for: Self.raw(.tab, [s("a", 3), s("b")])) == [s("a", 3), s("b")])
    }

    @Test func aFolderOfOneSearchOpensFiveWhenNoCountWasGiven() {
        // Arc: a folder with one search and a count of 1 opens 5.
        #expect(InstantLinks.openings(for: Self.raw(.folder, [s("iphone chargers")])) == [s("iphone chargers", 5)])
        #expect(InstantLinks.openings(for: Self.raw(.folder, [s("iphone chargers", 3)])) == [s("iphone chargers", 3)])
        #expect(InstantLinks.openings(for: Self.raw(.folder, [s("a"), s("b")])) == [s("a"), s("b")])
    }

    @Test func aSplitHasFourPanesAtMost() {
        #expect(InstantLinks.openings(for: Self.raw(.split, [s("lasagna recipes", 5)])) == [s("lasagna recipes", 4)])
        #expect(InstantLinks.openings(for: Self.raw(.split, [s("a", 3), s("b", 3)])) == [s("a", 3), s("b", 1)])
        #expect(InstantLinks.openings(for: Self.raw(.split, [s("a"), s("b")])) == [s("a"), s("b")])
        #expect(InstantLinks.openings(for: Self.raw(.split, [s("a", 4), s("b", 4), s("c", 4), s("d", 4), s("e")])).map(\.count) == [1, 1, 1, 1])
    }

    @Test func noMoreThanTenOpenAtOnce() {
        #expect(InstantLinks.openings(for: Self.raw(.tab, [s("a", 8), s("b", 8)])) == [s("a", 8), s("b", 2)])
        #expect(InstantLinks.openings(for: Self.raw(.folder, [s("a", 10), s("b", 3)])) == [s("a", 9), s("b", 1)])
        #expect(InstantLinks.openings(for: Self.raw(.tab, [s("a", 0)])) == [s("a")])
    }

    private static func raw(_ format: InstantLinks.Format, _ searches: [S]) -> InstantLinks.Plan {
        InstantLinks.Plan(title: "T", format: format, searches: searches)
    }

    // MARK: Google

    @Test func onlyGoogleResultsCanBeRead() {
        #expect(InstantLinks.readsResults(of: ChromiumSearchEngine(.google)))
        #expect(!InstantLinks.readsResults(of: ChromiumSearchEngine(.duckduckgo)))
        #expect(!InstantLinks.readsResults(of: ChromiumSearchEngine(.bing)))
        #expect(!InstantLinks.readsResults(of: ChromiumSearchEngine(.kagi)))
        #expect(!InstantLinks.readsResults(of: nil))
        // A Google the profile lists itself, on another country's domain.
        #expect(InstantLinks.readsResults(of: ChromiumSearchEngine(name: "Google", keyword: "google.it", url: "https://www.google.it/search?q={searchTerms}")))
    }

    @Test func googleURLEncodesTheQuery() {
        #expect(InstantLinks.googleURL(for: "barbie trailer").absoluteString == "https://www.google.com/search?q=barbie%20trailer")
        #expect(InstantLinks.googleURL(for: "mkbhd site:youtube.com").absoluteString == "https://www.google.com/search?q=mkbhd%20site:youtube.com")
        #expect(InstantLinks.googleURL(for: "tom & jerry #1").absoluteString == "https://www.google.com/search?q=tom%20%26%20jerry%20%231")
        #expect(InstantLinks.googleURL(for: "tiramisù").absoluteString == "https://www.google.com/search?q=tiramis%C3%B9")
    }

    @Test func theScriptReadsArcsSelectorsAndWaitsForThem() {
        let js = InstantLinks.resultsScript(limit: 5)
        for part in ["#main", ".//a[.//h3[not(@role='header') and not(@aria-hidden='true')]]", "div#botstuff, div#bottomads",
                     "form#captcha-form", "iframe[title='reCAPTCHA']", "div#recaptcha", "iframe[title='recaptcha']",
                     "JSON.stringify", "blocked", "setTimeout", "100"] {
            #expect(js.contains(part), "\(part)")
        }
    }

    @Test func resultsAreTheUsableLinksOfTheScriptsAnswer() {
        let json = """
        {"links": [
          "https://www.google.com/search?q=barbie&tbm=isch",
          "https://www.google.com/url?q=https://example.com/a%3Fx%3D1&sa=U",
          "https://www.google.com/goto?url=https%3A%2F%2Fexample.com%2Fb",
          "https://example.com/a?x=1",
          "https://www.google.com/maps/place/x",
          "https://accounts.google.com/signin",
          "javascript:alert(1)",
          "ftp://example.com/f",
          "https://docs.google.com/document/d/1",
          "https://example.org/c",
          "https://example.net/d"
        ], "blocked": false}
        """
        let r = InstantLinks.results(fromJSON: json, limit: 10)
        #expect(r.blocked == false)
        #expect(r.links.map(\.absoluteString) == [
            "https://example.com/a?x=1",
            "https://www.google.com/goto?url=https%3A%2F%2Fexample.com%2Fb",
            "https://docs.google.com/document/d/1",
            "https://example.org/c",
            "https://example.net/d",
        ])
        #expect(InstantLinks.results(fromJSON: json, limit: 2).links.count == 2)
    }

    @Test func aCaptchaIsReportedAndBadJSONIsEmpty() {
        #expect(InstantLinks.results(fromJSON: #"{"links": [], "blocked": true}"#, limit: 3) == .init(links: [], blocked: true))
        #expect(InstantLinks.results(fromJSON: "not json", limit: 3) == .init(links: [], blocked: false))
        #expect(InstantLinks.results(fromJSON: #"{"links": [1, null, "https://example.com"]}"#, limit: 3).links.count == 1)
        #expect(InstantLinks.results(fromJSON: #"{"links": ["https://example.com"]}"#, limit: 0).links.isEmpty)
    }

    // MARK: Without the model

    @Test func thePlainPlanReadsTheCueWords() {
        #expect(InstantLinks.plainPlan(for: "barbie trailer") == .init(title: "Barbie Trailer", format: .tab, searches: [s("barbie trailer")]))
        #expect(InstantLinks.plainPlan(for: "top 3 pizza places").searches == [s("top 3 pizza places", 3)])
        #expect(InstantLinks.plainPlan(for: "folder of iphone chargers").format == .folder)
        #expect(InstantLinks.plainPlan(for: "cartella pizza").format == .folder)
        #expect(InstantLinks.plainPlan(for: "pizza and pasta in a split").format == .split)
        #expect(InstantLinks.plainPlan(for: "pizza on the left and pasta on the right").format == .split)
    }

    @Test func instantLinksIsOffByDefaultAndRoundTrips() throws {
        #expect(AppSettings().instantLinks == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).instantLinks == false)
        var on = AppSettings()
        on.instantLinks = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).instantLinks)
        #expect(UsageStats.reportedSettings.contains("instantLinks"))
    }
}
