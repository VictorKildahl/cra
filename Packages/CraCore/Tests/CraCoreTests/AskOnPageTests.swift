import Foundation
import Testing
@testable import CraCore

/// Arc Max's Ask on Page (#393): Arc 1.173.1's find-or-ask bar, prompt and answer parts.
struct AskOnPageTests {
    @Test func asksOnlyAboutWebPagesAndFiles() {
        #expect(AskOnPagePolicy.canAsk(page: URL(string: "https://example.com/a")))
        #expect(AskOnPagePolicy.canAsk(page: URL(string: "http://example.com")))
        #expect(AskOnPagePolicy.canAsk(page: URL(string: "file:///Users/a/b.html")))
        #expect(!AskOnPagePolicy.canAsk(page: URL(string: "cra://settings")))
        #expect(!AskOnPagePolicy.canAsk(page: URL(string: "chrome://version")))
        #expect(!AskOnPagePolicy.canAsk(page: URL(string: "about:blank")))
        #expect(!AskOnPagePolicy.canAsk(page: nil))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func placeholdersAreArcs() {
        #expect(AskOnPagePolicy.placeholder(canAsk: false, inConversation: false) == "Find in page…")
        #expect(AskOnPagePolicy.placeholder(canAsk: true, inConversation: false) == "Find or ask…")
        #expect(AskOnPagePolicy.placeholder(canAsk: true, inConversation: true) == "Ask a question…")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func returnFindsTextOnThePageAndAsksTheRest() {
        let r = AskOnPagePolicy.returnKey
        #expect(r("", 3, false, true) == nil)
        #expect(r("   ", nil, true, true) == nil)
        #expect(r("solar", 3, false, true) == .nextMatch)
        #expect(r("how do reactions work", 0, false, true) == .ask)
        #expect(r("how do reactions work", nil, false, true) == .ask)
        #expect(r("solar", nil, false, true) == .nextMatch)
        // In a conversation the field only asks, even when the words are on the page.
        #expect(r("solar", 3, true, true) == .ask)
        // A page the card can't answer about keeps the plain find bar.
        #expect(r("how do reactions work", 0, false, false) == .nextMatch)
        #expect(AskOnPagePolicy.showsAskButton(query: "why", canAsk: true))
        #expect(!AskOnPagePolicy.showsAskButton(query: " ", canAsk: true))
        #expect(!AskOnPagePolicy.showsAskButton(query: "why", canAsk: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func promptIsArcsWithThePageBetweenItsTags() {
        let rules = AskOnPagePrompt.rules(language: "Danish")
        #expect(rules.hasPrefix("You will be acting as a research assistant."))
        #expect(rules.contains("7. Respond in Danish."))
        #expect(rules.contains("using an <excerpt> tag on its own line"))
        #expect(AskOnPagePrompt.instructions(language: "English").contains("EXAMPLES OF RESPONSES FOR A HYPOTHETICAL WEBPAGE:"))
        let p = AskOnPagePrompt.prompt(url: "https://apple.com/ios", title: "iOS 17", date: "12/11/2026, 18:00",
                                       text: "React with your hands.", turns: [], question: "How do reactions work?")
        #expect(p == """
        WEBPAGE CONTEXT FOR OUR DIALOGUE:
        <url>https://apple.com/ios</title>
        <current-date>12/11/2026, 18:00</current-date>
        <title>iOS 17</title>
        <content>
        React with your hands.
        </content>
        BEGIN DIALOGUE
        How do reactions work?
        """)
    }

    @Test func followUpsKeepTheLastAnswersAndHideOlderOnes() {
        let turns = (1...3).map { AskOnPagePrompt.Turn(question: "q\($0)", answer: "a\($0)") }
        #expect(AskOnPagePrompt.dialogue(turns: turns, question: "q4") == """
        BEGIN DIALOGUE
        Human: q1
        Assistant: [Older messages hidden]
        Human: q2
        Assistant: a2
        Human: q3
        Assistant: a3
        Human: q4
        """)
    }

    @Test func budgetIsArcsLessTheAnswersRoom() {
        // Arc: min(context, 16000) × 3 − (rules + examples + 200); the answer's 600 tokens off the context first.
        #expect(AskOnPagePrompt.characterBudget(contextTokens: 4096, instructions: String(repeating: "x", count: 2000), dialogue: "q")
                == (4096 - 600) * 3 - 2201)
        #expect(AskOnPagePrompt.characterBudget(contextTokens: 100_000, instructions: "", dialogue: "") == (16_000 - 600) * 3 - 200)
        #expect(AskOnPagePrompt.characterBudget(contextTokens: 100, instructions: "", dialogue: "") == 0)
        #expect(AskOnPagePrompt.shrink(budget: 9000, promptTokens: 4000, allowedTokens: 3000) == 6075)
        #expect(AskOnPagePrompt.shrink(budget: 9000, promptTokens: 2000, allowedTokens: 3000) == 9000)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func longPagesAreCutAndSaySo() {
        let page = String(repeating: "a", count: 1000)
        let short = AskOnPagePrompt.truncate(page, budget: 2000)
        #expect(short.text == page)
        #expect(short.fractionRead == nil)
        let cut = AskOnPagePrompt.truncate(page, budget: 810)
        #expect(cut.text == String(repeating: "a", count: 810) + "…")
        #expect(cut.fractionRead == 0.81)
        #expect(AskOnPagePrompt.fractionLine(cut.fractionRead) == "This page was long, so I read the first 81%.")
        // The script read 1000 characters of a 4000-character page: the share is of the whole page.
        #expect(AskOnPagePrompt.truncate(page, budget: 2000, total: 4000).fractionRead == 0.25)
        #expect(AskOnPagePrompt.fractionLine(nil) == nil)
        #expect(AskOnPagePrompt.fractionLine(1) == nil)
        #expect(AskOnPagePrompt.fractionLine(0.999) == "This page was long, so I read the first 99%.")
        #expect(AskOnPagePrompt.fractionLine(0.001) == "This page was long, so I read the first 1%.")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func answersSplitIntoTextAndQuotes() {
        let reply = """
        According to the page:
        <excerpt>"React with your hands Add a reaction that fills the camera frame."</excerpt>
        You can add reactions like **hearts** during a FaceTime call.
        """
        #expect(AskOnPageReply.parts(reply) == [
            .init(text: "According to the page:", isQuote: false),
            .init(text: "React with your hands Add a reaction that fills the camera frame.", isQuote: true),
            .init(text: "You can add reactions like **hearts** during a FaceTime call.", isQuote: false),
        ])
        #expect(AskOnPageReply.parts("I think it’s **Brooklyn**.") == [.init(text: "I think it’s **Brooklyn**.", isQuote: false)])
    }

    @Test func aStreamingAnswerShowsItsQuoteAsItComes() {
        #expect(AskOnPageReply.parts("According to the page:\n<exc") == [.init(text: "According to the page:", isQuote: false)])
        #expect(AskOnPageReply.parts("According to the page:\n<excerpt>React with") == [
            .init(text: "According to the page:", isQuote: false), .init(text: "React with", isQuote: true),
        ])
        #expect(AskOnPageReply.parts("A\n<excerpt>React with your</exce") == [
            .init(text: "A", isQuote: false), .init(text: "React with your", isQuote: true),
        ])
        #expect(AskOnPageReply.parts("") == [])
        #expect(AskOnPageReply.parts("a < b") == [.init(text: "a < b", isQuote: false)])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func theModelsEchoOfTheDialogueIsLeftOut() {
        // The on-device model wrote these back before its answer on Wikipedia's Solar power page.
        let reply = "BEGIN DIALOGUE\nHuman: What share of the world's electricity came from solar?\n<excerpt>In 2025, solar power generated 9% of global electricity.</excerpt>\nSolar power accounted for **9%**."
        #expect(AskOnPageReply.parts(reply) == [
            .init(text: "In 2025, solar power generated 9% of global electricity.", isQuote: true),
            .init(text: "Solar power accounted for **9%**.", isQuote: false),
        ])
        #expect(AskOnPageReply.parts("Assistant: According to the page:") == [.init(text: "According to the page:", isQuote: false)])
        #expect(AskOnPageReply.parts("BEGIN DIA") == [])
        #expect(AskOnPageReply.parts("Hum") == [])
        #expect(AskOnPageReply.parts("Hello there") == [.init(text: "Hello there", isQuote: false)])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393")) func aQuoteSplitByThePagesFootnoteIsFoundByItsFirstSentence() {
        // Wikipedia shows "…9% of global electricity.[3] In 2024, …": the whole quote isn't on the page.
        let quote = "In 2025, solar power generated 9% of global electricity. In 2024, solar generated 7% of global electricity and over 1% of primary energy."
        #expect(AskOnPageReply.findCandidates(quote) == [
            "In 2025, solar power generated 9% of global electricity. In 2024, solar generated 7% of global electricity and over 1% of primary energy",
            "In 2025, solar power generated 9% of global electricity",
            "In 2025, solar power generated 9% of global",
        ])
        #expect(AskOnPageReply.findCandidates("Short quote.") == ["Short quote"])
    }

    @Test func quotesAreFoundByTheWordsThePageShows() {
        #expect(AskOnPageReply.findText("“[Privacy Policy](https://x.com/p)”") == "Privacy Policy")
        #expect(AskOnPageReply.findText(" React with   your **hands**.") == "React with your hands")
        #expect(AskOnPagePolicy.trimQuote("\"‘quoted’\"") == "quoted")
    }

    @Test func theTestModelQuotesTheSentenceThatAnswers() {
        let text = "Welcome to the page. Reactions fill the camera frame with effects. Other things here."
        let answer = AskOnPagePrompt.fakeAnswer(question: "How do reactions work?", text: text)
        #expect(AskOnPageReply.parts(answer).contains(.init(text: "Reactions fill the camera frame with effects.", isQuote: true)))
    }

    @Test func pageScriptLeavesOutArcsSkippedParts() {
        let s = AskOnPagePolicy.pageTextScript
        for part in ["nav", "footer", "header", "form", "[aria-hidden=true]", "[itemprop=mainEntity]", "article", "#content"] {
            #expect(s.contains(part))
        }
        #expect(s.contains("200000"))
    }

    @Test func askOnPageIsOffByDefaultAndRoundTrips() throws {
        #expect(AppSettings().askOnPage == false)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).askOnPage == false)
        var on = AppSettings()
        on.askOnPage = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).askOnPage)
        #expect(UsageStats.reportedSettings.contains("askOnPage"))
    }
}

struct AskOnPageToneTests {
    @Test func theSpacesHueAtAReadableStrength() {
        // Arc's lavender space (#B9A3D9-ish) gives a mid purple: blue and red over green.
        let purple = AskOnPageTone.accent(themeHex: "#B9A3D9", dark: false)
        #expect(purple.b > purple.r && purple.r > purple.g)
        #expect(max(purple.r, purple.g, purple.b) == 0.62)
        let grey = AskOnPageTone.accent(themeHex: "#DDDDDD", dark: false)
        #expect(grey.r == 0.22 && grey.b == 1)
        #expect(max(AskOnPageTone.accent(themeHex: "#B9A3D9", dark: true).b, 0) == 0.92)
    }
}
