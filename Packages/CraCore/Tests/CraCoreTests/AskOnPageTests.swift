@testable import CraCore
import Foundation
import Testing

struct AskOnPageTests {
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
        #expect(max(purple.r, purple.g, purple.b) == 0.62)
        let grey = AskOnPageTone(themeHex: "#DDDDDD").questionOnLight
        #expect(abs(grey.r - 0.22) < 0.005 && abs(grey.g - 0.24) < 0.005 && abs(grey.b - 1) < 0.005)
        // On the dark card the same purple is light and keeps its hue.
        let onDark = AskOnPageTone(themeHex: "#B9A3D9").questionOnDark
        #expect(onDark.b > onDark.r && onDark.r > onDark.g && onDark.b >= 0.92)
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

}
