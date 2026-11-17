@testable import CraCore
import Foundation
import Testing

struct AskOnPageTests {
    @Test func aFloatingToolbarLeavesTheAskCardInsideAShortFocusedPage() {
        let page = CGRect(x: 290, y: 10, width: 240, height: 180)
        let preferred = CGSize(width: 400, height: 499)
        let hidden = AskOnPageLayout.frame(preferred: preferred, page: page, inset: 10)
        let shown = AskOnPageLayout.frame(preferred: preferred, page: page, inset: 10, toolbarOverPage: 32)
        #expect(shown.maxY == hidden.maxY - 32)
        #expect(shown.height == hidden.height - 32)
        #expect(shown.minY == page.minY + 10)
        #expect(shown.width == 220 && shown.maxX == page.maxX - 10)
        let covered = AskOnPageLayout.frame(preferred: preferred, page: page, inset: 10, toolbarOverPage: 300)
        #expect(covered.height == 0 && covered.maxY == page.minY)
    }

    @Test func findFinalZeroBelongsToTheExactCurrentQueryGeneration() {
        var find = AskOnPage.FindState()
        let a = find.begin("absent")
        let acceptsPartial = find.accept(a.id, quote: false, identifier: 1, count: 0, activeMatch: 0, finalUpdate: false)
        #expect(acceptsPartial)
        #expect(!find.canAsk(query: "absent", enabled: true, forward: true))
        let b = find.begin("matching")
        let rejectsOldZero = !find.accept(a.id, quote: false, identifier: 1, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(rejectsOldZero)
        #expect(find.count == nil && !find.canAsk(query: "matching", enabled: true, forward: true))
        let acceptsMatching = find.accept(b.id, quote: false, identifier: 2, count: 3, activeMatch: 1, finalUpdate: true)
        #expect(acceptsMatching)
        #expect(find.count == 3 && find.activeMatch == 1 && !find.canAsk(query: "matching", enabled: true, forward: true))
        let again = find.begin("absent")
        #expect(again.id != a.id)
        let rejectsFirstA = !find.accept(a.id, quote: false, identifier: 1, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(rejectsFirstA)
        let acceptsNewZero = find.accept(again.id, quote: false, identifier: 3, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(acceptsNewZero)
        #expect(find.canAsk(query: "absent", enabled: true, forward: true))
        #expect(!find.canAsk(query: "absent", enabled: false, forward: true))
        #expect(!find.canAsk(query: "absent", enabled: true, forward: false))
        #expect(!find.canAsk(query: "edited before native Find", enabled: true, forward: true))
        let continuesSession = find.begin("absent").id == again.id
        #expect(continuesSession, "next/previous keep the same query session")
        find.clear()
        let rejectsClosed = !find.accept(again.id, quote: false, identifier: 3, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(rejectsClosed)
        let reopensFresh = find.begin("absent").id != again.id
        #expect(reopensFresh, "reopening identical text starts a fresh session")
    }

    @Test func quoteUnknownAndEmptyFindResultsNeverAuthorizeAsk() {
        for query in ["", "\r", " "] {
            var find = AskOnPage.FindState()
            let request = find.begin(query)
            _ = find.accept(request.id, quote: false, identifier: 0, count: 0, activeMatch: 0, finalUpdate: true)
            #expect(!find.canAsk(query: query, enabled: true, forward: true))
        }
        var find = AskOnPage.FindState()
        let request = find.begin("a question")
        let rejectsWrongPurpose = !find.accept(request.id, quote: true, identifier: 1, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(rejectsWrongPurpose)
        _ = find.accept(request.id, quote: false, identifier: 1, count: 0, activeMatch: 0, finalUpdate: false)
        _ = find.accept(request.id, quote: false, identifier: 1, count: -1, activeMatch: -1, finalUpdate: true)
        #expect(!find.canAsk(query: "a question", enabled: true, forward: true), "a negative final must not promote a partial zero")
        let quote = find.begin("a question", purpose: .quote)
        #expect(quote.id != request.id)
        _ = find.accept(quote.id, quote: true, identifier: 2, count: 0, activeMatch: 0, finalUpdate: true)
        #expect(!find.canAsk(query: "a question", enabled: true, forward: true))
        let restoresOrdinary = find.begin("a question").id != quote.id
        #expect(restoresOrdinary, "restoring ordinary Find uses a new session")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func quotesRequireTheExactTransmittedSource() throws {
        let draft = AskOnPage.Draft(excerpts: ["The answer is solar power."], answer: "Mostly solar power.", keyAnswer: "solar power")
        let valid = try #require(AskOnPage.completeAnswer(draft, source: "The answer is solar\n\t power."))
        #expect(valid.quotes.first?.state == .verified && valid.hasVerifiedQuote)
        #expect(valid.emphasisRange == NSRange(location: 7, length: 11))
        #expect(AskOnPage.completeAnswer(draft, source: "The answer is Solar power.")?.quotes.first?.state == .notFound)
        #expect(AskOnPage.completeAnswer(draft, source: "The answer is solar power!")?.quotes.first?.state == .notFound)
        #expect(AskOnPage.completeAnswer(draft, source: "This is only the transmitted page introduction.")?.hasVerifiedQuote == false)
    }

    /// The model types a hyphen and straight quotes where the page prints an en dash and curly quotes
    /// (Wikipedia's "designed in 1956–1957"): the same punctuation, so the quote is on the page, and Find
    /// looks for the page's own characters. A different mark ("!" for ".") still isn't.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func typographicVariantsOfTheSamePunctuationMatch() throws {
        let source = "Helvetica is a typeface designed in 1956–1957 by Max Miedinger. It was called “Neue Haas Grotesk” at first."
        let draft = AskOnPage.Draft(excerpts: ["designed in 1956-1957 by Max Miedinger.", "It was called \"Neue Haas Grotesk\" at first."],
                                    answer: "Max Miedinger.", keyAnswer: "Max Miedinger")
        let answer = try #require(AskOnPage.completeAnswer(draft, source: source))
        #expect(answer.quotes.map(\.state) == [.verified, .verified])
        #expect(answer.quotes.map(\.findText) == ["designed in 1956–1957 by Max Miedinger.", "It was called “Neue Haas Grotesk” at first."])
        #expect(answer.quotes.map(\.text) == draft.excerpts, "the card shows the answer's quote as written")
        let other = AskOnPage.Draft(excerpts: ["designed in 1956-1957 by Max Miedinger!"], answer: "Max Miedinger.", keyAnswer: nil)
        #expect(AskOnPage.completeAnswer(other, source: source)?.quotes.first?.state == .notFound)
        let exact = try #require(AskOnPage.completeAnswer(.init(excerpts: ["It was called"], answer: "Yes.", keyAnswer: nil), source: source))
        #expect(exact.quotes.first?.findText == "It was called")
    }

    @Test func literalSourceCharactersAreDataRatherThanMarkup() throws {
        let source = "Budget < €40 & the editor says \"use <excerpt> literally\". Café stays unchanged."
        let quote = "Budget < €40 & the editor says \"use <excerpt> literally\"."
        let answer = try #require(AskOnPage.completeAnswer(.init(excerpts: [quote, "Cafe\u{301} stays unchanged."],
            answer: "Budget is below €40.", keyAnswer: "€40"), source: source))
        #expect(answer.quotes.map(\.text) == [quote, "Cafe\u{301} stays unchanged."])
        #expect(answer.quotes.allSatisfy { $0.state == .verified })
        #expect(!answer.historyText.contains("&lt;"), "native rendering/history retain actual visible source text")
        let encoded = quote.replacingOccurrences(of: "<", with: "&lt;")
        #expect(AskOnPage.completeAnswer(.init(excerpts: [encoded], answer: "Budget is below €40.", keyAnswer: "€40"), source: source)?.hasVerifiedQuote == false)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func partialFieldsNeverEnableEvidence() {
        let partial = AskOnPage.partialAnswer(.init(excerpts: ["A fact."], answer: "A fact", keyAnswer: "fact"))
        #expect(!partial.isComplete && !partial.hasVerifiedQuote && partial.quotes.first?.state == .unverified)
        #expect(AskOnPage.partialAnswer(.init()).text.isEmpty)
    }

    @Test func joinedEmojiAndPersianFormatScalarsSurviveNativeAnswers() throws {
        let text = "👩‍💻 می‌روم"
        let answer = try #require(AskOnPage.completeAnswer(.init(excerpts: [text], answer: text, keyAnswer: "می‌روم"), source: text))
        #expect(answer.text == text && answer.quotes.first?.text == text && answer.hasVerifiedQuote)
        #expect(answer.emphasisRange == NSRange(location: 6, length: 6))
        #expect(AskOnPage.partialAnswer(.init(excerpts: [text], answer: text, keyAnswer: "می‌روم")).text == text)
    }

    @Test func zeroOrInvalidCitationsDoNotInvalidateAnOtherwiseCompleteAnswer() throws {
        let guess = try #require(AskOnPage.completeAnswer(.init(excerpts: [], answer: "I guess Brooklyn, but it is not on the page.", keyAnswer: "Brooklyn"), source: "A fact."))
        #expect(guess.isComplete && guess.quotes.isEmpty && !guess.hasVerifiedQuote)
        let mixed = try #require(AskOnPage.completeAnswer(.init(excerpts: ["A fact.", "An invention."], answer: "A mixed answer.", keyAnswer: "mixed"), source: "A fact."))
        #expect(mixed.quotes.map(\.state) == [.verified, .notFound])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417"), arguments: [
        // The reporter's questions on a release page (13 Nov 2026), and other ways to ask for one.
        "summarize the top featuress", "list out all the features released today", "Summarize this page.",
        "summarise it in bullet points", "what are the key points?", "tl;dr", "TLDR please", "give me an overview of the history",
        "List the main exports", "make a list of the fixes", "Sum up the article", "What are the main takeaways?",
    ])
    func aSummaryOrAListIsAnsweredWithoutQuotes(question: String) {
        #expect(AskOnPage.Form(question: question) == .summary)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417"), arguments: [
        // Questions keep Arc's quote and short answer; so does a summary that asks for quotes.
        "what is Instant Links?", "When did Haiti become independent?", "Is the moon on the list?", "Who listed it?",
        "summarize with quotes from the page", "List the fixes with references", "give me a summary and cite the page",
        "Where does it say the summary is due?", "What is a bulletin?",
    ])
    func aQuestionOrAnAskedForQuoteIsAnsweredWithQuotes(question: String) {
        #expect(AskOnPage.Form(question: question) == .quoted)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417")) func aSummarysPointsEachGetALineOnce() {
        // The model's points for "give me a short summary of the fixes" on a page with three fixes.
        let points = ["A ⌃, ⌥ or F-key App Shortcut works while a page has the keyboard.", "• A space’s emoji draws itself.",
                      " ", "Docked pages keep square corners.", "A ⌃, ⌥ or F-key App Shortcut works while a page has the keyboard.",
                      "a space’s  emoji draws itself."]
        let listed = AskOnPage.listed(points: points)
        #expect(listed == "• A ⌃, ⌥ or F-key App Shortcut works while a page has the keyboard.\n• A space’s emoji draws itself.\n• Docked pages keep square corners.")
        #expect(AskOnPage.lines(listed).count == 3)
        #expect(AskOnPage.listed(points: []).isEmpty)
    }

    @Test func completeRequiredFieldsAreStillRequired() {
        for draft in [AskOnPage.Draft(answer: "Answer", keyAnswer: "Answer"), .init(excerpts: [], keyAnswer: "Answer"),
                      .init(excerpts: [], answer: " ", keyAnswer: " ")] {
            #expect(AskOnPage.completeAnswer(draft, source: "A fact.") == nil)
        }
    }

    @Test(arguments: [nil, "", "09:30 Elm Street", "a 09:30"] as [String?])
    func unusableEmphasisKeepsTheExactNativeAnswer(hint: String?) throws {
        let text = "L'observatoire ouvre à 09:30 sur Elm Street."
        let answer = try #require(AskOnPage.completeAnswer(.init(excerpts: ["A fact."], answer: text, keyAnswer: hint), source: "A fact."))
        #expect(answer.text == text && answer.historyText.contains(text))
        #expect(answer.emphasisRange == nil && answer.quotes.first?.state == .verified)
    }

    @Test func transformationsCanBeMultilineAndEmphasizeTheWholeAnswer() throws {
        let text = "Première ligne: une traduction complète.\nDeuxième ligne: encore une phrase, au-delà de dix mots."
        let result = try #require(AskOnPage.completeAnswer(.init(excerpts: [], answer: text, keyAnswer: text), source: "Original page"))
        #expect(result.text == text && result.emphasisRange == NSRange(location: 0, length: text.utf16.count))
    }

    @Test func nativeFieldBoundsPreserveGraphemesAndRejectOversizedFinals() {
        let draft = AskOnPage.Draft(excerpts: ["A fact."], answer: String(repeating: "📄", count: 20_000), keyAnswer: "📄")
        let partial = AskOnPage.partialAnswer(draft)
        #expect(partial.text.utf8.count <= 65_536 && partial.text.allSatisfy { $0 == "📄" })
        #expect(AskOnPage.completeAnswer(draft, source: "A fact.") == nil)
        #expect(AskOnPage.completeAnswer(.init(excerpts: Array(repeating: "A fact.", count: 5), answer: "Fact", keyAnswer: "Fact"), source: "A fact.") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func historyEvictsWholePairsAndRemembersTheOmission() {
        var history = AskOnPage.History()
        for n in 0...12 { history.append(.init(question: "Question \(n)", answer: "Answer \(n)")) }
        #expect(history.turns.count == 12)
        #expect(history.turns.first == .init(question: "Question 1", answer: "Answer 1"))
        #expect(history.turns.last == .init(question: "Question 12", answer: "Answer 12"))
        #expect(history.olderMessagesHidden)
        history.append(.init(question: "New question", answer: String(repeating: "📄", count: 17_000)))
        #expect(history.turns.isEmpty, "an oversized pair is omitted, never split")
        history.append(.init(question: "Small question", answer: "Small answer"))
        #expect(history.turns == [.init(question: "Small question", answer: "Small answer")])
        #expect(history.olderMessagesHidden)
    }
}

struct AskOnPageNativePresentationTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393"))
    func fixtureQuotesTheActualFittedSentenceWithoutRepair() throws {
        let source = "Welcome to the page. Reactions fill the camera frame with effects! Other things here."
        let draft = AskOnPage.fixtureDraft(question: "How do reactions work?", source: source)
        let answer = try #require(AskOnPage.completeAnswer(draft, source: source))
        #expect(answer.quotes.map(\.text) == ["Reactions fill the camera frame with effects!"])
        #expect(answer.quotes.first?.state == .verified)
        #expect(!answer.text.contains("<excerpt>"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393"))
    func pageFractionDisclosureKeepsItsVisibleWording() {
        #expect(AskOnPagePrompt.fractionLine(0.81) == "This page was long, so I read the first 81%.")
        #expect(AskOnPagePrompt.fractionLine(nil) == nil)
        #expect(AskOnPagePrompt.fractionLine(1) == nil)
        #expect(AskOnPagePrompt.fractionLine(0.999) == "This page was long, so I read the first 99%.")
        #expect(AskOnPagePrompt.fractionLine(0.001) == "This page was long, so I read the first 1%.")
    }
}

struct AskOnPagePolicyTests {
    @Test func eligibilityMatchesLegacyWebAndPrivateTypeRules() {
        for scheme in ["http", "https", "HTTP", "HTTPS"] {
            #expect(AskOnPagePolicy.canAsk(page: URL(string: "\(scheme)://example.test/article"), incognito: false, documentKind: .html))
        }
        for url in [nil, "file:///tmp/article.html", "cra://settings", "chrome://version", "about:blank", "https://search.arc.net/path", "https://SEARCH.ARC.NET/path", "https://SeArCh.ArC.NeT/path"] as [String?] {
            #expect(!AskOnPagePolicy.canAsk(page: url.flatMap(URL.init(string:)), incognito: false, documentKind: .unknown))
        }
        for kind in [AskOnPagePolicy.DocumentKind.pdf, .image, .movie] {
            #expect(!AskOnPagePolicy.canAsk(page: URL(string: "https://example.test/extensionless"), incognito: false, documentKind: kind))
        }
        for kind in [AskOnPagePolicy.DocumentKind.unknown, .html, .other] {
            #expect(AskOnPagePolicy.canAsk(page: URL(string: "https://example.test/article"), incognito: false, documentKind: kind))
            #expect(!AskOnPagePolicy.canAsk(page: URL(string: "https://example.test/article"), incognito: true, documentKind: kind))
        }
        #expect(AskOnPagePolicy.canAsk(page: URL(string: "https://sub.search.arc.net/article"), incognito: false, documentKind: .html))
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func placeholdersAreArcs() {
        #expect(AskOnPagePolicy.placeholder(canAsk: false, inConversation: false) == "Find in page…")
        #expect(AskOnPagePolicy.placeholder(canAsk: true, inConversation: false) == "Find or ask…")
        #expect(AskOnPagePolicy.placeholder(canAsk: true, inConversation: true) == "Ask a question…")
    }

    @Test func askOnPageIsOffByDefaultAndRoundTrips() throws {
        #expect(AppSettings().askOnPage == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).askOnPage == false)
        var on = AppSettings()
        on.askOnPage = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).askOnPage)
        #expect(UsageStats.reportedSettings.contains("askOnPage"))
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393"))
    func returnRequiresAnOwnedFinalZeroAndNeverAsksBackward() {
        let r = AskOnPagePolicy.returnKey
        #expect(r("", true, false, true, true) == nil)
        #expect(r("   ", true, true, true, true) == nil)
        #expect(r("solar", false, false, true, true) == .nextMatch)
        #expect(r("how do reactions work", false, false, true, true) == .nextMatch)
        #expect(r("how do reactions work", true, false, true, true) == .ask)
        #expect(r("how do reactions work", true, false, true, false) == .nextMatch)
        #expect(r("solar", false, true, true, true) == .ask)
        #expect(r("solar", true, true, true, false) == .nextMatch)
        #expect(r("question", true, false, false, true) == .nextMatch)
        #expect(AskOnPagePolicy.showsAskButton(query: "why", canAsk: true))
        #expect(!AskOnPagePolicy.showsAskButton(query: " ", canAsk: true))
        #expect(!AskOnPagePolicy.showsAskButton(query: "why", canAsk: false))
    }
}

struct AskOnPageToneTests {
    @Test func theSpacesHueAtAReadableStrength() {
        // Arc's lavender space (#B9A3D9-ish) gives a mid purple: blue and red over green.
        let purple = AskOnPageTone(themeHex: "#B9A3D9").questionOnLight
        #expect(purple.b > purple.r && purple.r > purple.g)
        #expect(max(purple.r, purple.g, purple.b) > 0.5 && max(purple.r, purple.g, purple.b) < 0.75)
        let grey = AskOnPageTone(themeHex: "#DDDDDD").questionOnLight
        #expect(abs(grey.r - 0.22) < 0.005 && abs(grey.g - 0.24) < 0.005 && abs(grey.b - 1) < 0.005)
        // On the dark card the same purple is light and keeps its hue.
        let onDark = AskOnPageTone(themeHex: "#B9A3D9").questionOnDark
        #expect(onDark.b > onDark.r && onDark.r > onDark.g)
    }

    /// Every preset's colours and the hue wheel at several strengths, on both cards: the question
    /// reads at WCAG AA, and so does the Ask button's white text. Before #408 the dark card showed
    /// the light card's purple at 2–3:1, and a saturated blue space read 1.5:1 even on its own card.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/408")) func everyQuestionReadsOnItsCard() {
        var swatches = SpaceTheme.presets.flatMap { [$0.accent].compactMap { $0 } + $0.colors }
        swatches += ["#DDDDDD", "#000000", "#FFFFFF", "#C7CAFF", "#0000FF", "#FFFF00", "#00FF00", "#FF0000"]
        for hue in stride(from: 0, to: 360, by: 15) {
            for (s, v) in [(0.2, 0.9), (0.6, 0.6), (1.0, 1.0), (1.0, 0.3)] {
                let c = AskOnPageTone.rgb(h: Double(hue) / 360, s: s, v: v)
                swatches.append(String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255)))
            }
        }
        let white: AskOnPageTone.RGB = (1, 1, 1)
        for hex in swatches {
            let tone = AskOnPageTone(themeHex: hex)
            for dark in [false, true] {
                let card = AskOnPageTone.card(dark: dark)
                let ratio = AskOnPageTone.contrast(tone.question(dark: dark), (card, card, card))
                #expect(ratio >= 4.5, "\(hex) on the \(dark ? "dark" : "light") card: \(ratio)")
            }
            #expect(AskOnPageTone.contrast(tone.button, white) >= 4.5, "Ask on \(hex)")
        }
    }

    static func hsl(_ c: AskOnPageTone.RGB) -> (h: Double, s: Double, l: Double) {
        let x = SpaceTheme.hsl(RGB(c.r, c.g, c.b)); return (x.h, x.s, x.l)
    }

    /// #490: the card kept only the space's hue and raised its saturation (to 0.55 on the light card),
    /// so a sage space asked in a loud green. It now moves only the space colour's lightness: Arc's muted
    /// sage and slate swatches keep their saturation on both cards, a vivid green is never bolder than
    /// itself, and every one still reads at 4.5:1.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/490"), arguments: ["#7AA982", "#666789", "#226149", "#34E895"])
    func theCardKeepsTheSpacesSaturation(hex: String) {
        let tone = AskOnPageTone(themeHex: hex)
        let own = HexColor.components(hex)!
        let source = Self.hsl((own.r, own.g, own.b))
        for (dark, q) in [(false, tone.questionOnLight), (true, tone.questionOnDark)] {
            let got = Self.hsl(q)
            #expect(abs(got.s - source.s) < 0.03 || got.l < 0.02 || got.l > 0.98, "\(hex) \(dark ? "dark" : "light"): s \(got.s) vs \(source.s)")
            #expect(abs(got.h - source.h) < 0.01, "\(hex) hue")
            let card = AskOnPageTone.card(dark: dark)
            #expect(AskOnPageTone.contrast(q, (card, card, card)) >= 4.5)
        }
        // Sage and slate stay muted (the old recipe pushed both past 0.55).
        if hex == "#7AA982" || hex == "#666789" { #expect(Self.hsl(tone.button).s < 0.3) }
    }

    /// The colourless default asks in Arc's default blue at mid strength, not its near-black navy half.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/490"), arguments: ["#010220", "#C8CAFF"])
    func theColourlessDefaultAsksInArcsBlue(hex: String) {
        let b = AskOnPageTone(themeHex: hex).button
        #expect(b.b > b.r && b.b > b.g && AskOnPageTone.luminance(b) > 0.05)
    }

    /// The reporter's case: a light space (Arc's lavender preset) with macOS dark. The dark card's
    /// question is a light lavender, not the light card's purple.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/408")) func lightSpaceOnDarkMacGetsALightQuestion() {
        let tone = AskOnPageTone(themeHex: "#C8CAFF")
        let q = tone.questionOnDark
        #expect(AskOnPageTone.luminance(q) > 0.25)
        #expect(q.b > q.g)
        #expect(AskOnPageTone.luminance(tone.questionOnLight) < 0.2)
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393"))
    func askLayoutCapsConversationAndFitsTheFocusedPage() {
        for page in [CGRect(x: 100, y: 200, width: 900, height: 700), CGRect(x: -600, y: 40, width: 240, height: 160),
                     CGRect(x: 1, y: 2, width: 8, height: 6), .zero] {
            let panel = AskOnPageLayout.frame(preferred: CGSize(width: 400, height: 498), page: page, inset: 10)
            #expect(panel.width >= 0 && panel.width <= 400 && panel.height >= 0)
            #expect(panel.minX >= page.minX && panel.maxX <= page.maxX && panel.minY >= page.minY && panel.maxY <= page.maxY)
        }
        let wide = AskOnPageLayout.frame(preferred: CGSize(width: 400, height: 498),
                                        page: CGRect(x: 0, y: 0, width: 900, height: 700), inset: 10)
        #expect(wide.size == CGSize(width: 400, height: 498))
        #expect(AskOnPageLayout.conversationHeight(content: 900, input: 48, available: 700) == 450)
        #expect(AskOnPageLayout.conversationHeight(content: 100, input: 48, available: 700) == 100)
        #expect(AskOnPageLayout.conversationHeight(content: 900, input: 48, available: 140) == 92)
        #expect(AskOnPageLayout.conversationHeight(content: 900, input: 100, available: 80) == 0)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417")) func aStreamedAnswerReachesTheCardTenTimesASecond() {
        var pacing = AskOnPageStreamPacing()
        #expect(pacing.delay(at: 5.0) == 0)
        pacing.shown(at: 5.0)
        #expect(abs(pacing.delay(at: 5.02) - 0.08) < 1e-9)
        #expect(pacing.delay(at: 5.1) == 0)
        #expect(pacing.delay(at: 7) == 0)
        // Fifty snapshots a second for two seconds: about twenty reach the card.
        var p = AskOnPageStreamPacing(), shown = 0, due: TimeInterval?
        for i in 0..<100 {
            let now = Double(i) * 0.02
            if let d = due, now >= d { p.shown(at: d); shown += 1; due = nil }
            if due == nil {
                let wait = p.delay(at: now)
                if wait == 0 { p.shown(at: now); shown += 1 } else { due = now + wait }
            }
        }
        #expect((19...21).contains(shown))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417")) func aStreamingAnswerIsDrawnLineByLine() {
        #expect(AskOnPage.lines("Key points:\n\n• one\n• two") == ["Key points:", " ", "• one", "• two"])
        #expect(AskOnPage.lines("one line") == ["one line"])
    }
}
