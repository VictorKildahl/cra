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
        let c = AskOnPagePrompt.conversation(url: "https://apple.com/ios", title: "iOS 17", date: "12/11/2026, 18:00",
                                             text: "React with your hands.", turns: [], question: "How do reactions work?")
        #expect(c.earlier.isEmpty)
        #expect(c.prompt == """
        WEBPAGE CONTEXT FOR OUR DIALOGUE:
        <url>https://apple.com/ios</title>
        <current-date>12/11/2026, 18:00</current-date>
        <title>iOS 17</title>
        <content>
        React with your hands.
        </content>
        How do reactions work?
        """)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417")) func theModelIsNotToldToWriteADialogue() {
        // Arc's "When I write BEGIN DIALOGUE … the "Human:"" made the on-device model write a dialogue
        // of its own: made-up questions, or the answer before word for word.
        let instructions = AskOnPagePrompt.instructions(language: "English")
        #expect(!instructions.contains("BEGIN DIALOGUE"))
        #expect(!instructions.contains("\"Human:\""))
        #expect(instructions.contains(AskOnPagePrompt.userLine))
    }

    @Test func theModelIsShownNoQuotesFromAnotherPage() {
        // Arc's examples quoted a solar-power page; the on-device model quoted it back as this page's.
        let instructions = AskOnPagePrompt.instructions(language: "English")
        for example in ["EXAMPLES OF RESPONSES", "J.W. Peters", "Solar Power of Oklahoma", "Brooklyn", "Privacy Policy"] {
            #expect(!instructions.contains(example))
        }
        #expect(instructions.contains("using an <excerpt> tag on its own line"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/417")) func aFollowUpIsItsOwnTurnAfterThePage() {
        // The reporter's conversation: the first answer stays a turn of its own, the follow-up is
        // asked alone, and no text says "Human:" or "Assistant:" for the model to carry on.
        let first = AskOnPagePrompt.Turn(question: "why el salvador succeed?",
                                         answer: "It cannot be determined from the page.\n<excerpt>The real measure of success.</excerpt>")
        let c = AskOnPagePrompt.conversation(url: "https://example.com/haiti", title: "Haiti", date: "13/11/2026, 12:00",
                                             text: "The real measure of success.", turns: [first],
                                             question: "Summarize the key points of this entire article in detailed bullet points.")
        #expect(c.prompt == "Summarize the key points of this entire article in detailed bullet points." + AskOnPagePrompt.followUpReminder)
        #expect(c.earlier == [.init(prompt: AskOnPagePrompt.context(url: "https://example.com/haiti", title: "Haiti", date: "13/11/2026, 12:00",
                                                                     text: "The real measure of success.") + "why el salvador succeed?",
                                    response: first.answer)])
        let sent = ([c.prompt] + c.earlier.flatMap { [$0.prompt, $0.response] }).joined(separator: "\n")
        for framing in ["BEGIN DIALOGUE", "Human:", "Assistant:"] { #expect(!sent.contains(framing)) }
    }

    @Test func aFollowUpIsAskedForAQuote() {
        // After a summary the model kept answering without quotes; the first question needs no reminder.
        let first = AskOnPagePrompt.conversation(url: "u", title: nil, date: "d", text: "page", turns: [], question: "q1")
        #expect(!first.prompt.contains(AskOnPagePrompt.followUpReminder))
        let next = AskOnPagePrompt.conversation(url: "u", title: nil, date: "d", text: "page",
                                                turns: [.init(question: "Summarize it", answer: "* one\n* two")], question: "Who?")
        #expect(next.prompt == "Who?\n\nQuote the page in an <excerpt> tag if it answers this.")
        #expect(next.earlier.map(\.prompt).allSatisfy { !$0.contains(AskOnPagePrompt.followUpReminder) })
    }

    @Test func aLongEarlierAnswerLeavesTheNextQuestionThePage() {
        let summary = String(repeating: "* A key point of the article.\n", count: 100)
        let c = AskOnPagePrompt.conversation(url: "u", title: nil, date: "d", text: "page",
                                             turns: [.init(question: "Summarize it", answer: summary)], question: "Who?")
        #expect(c.earlier[0].response == String(summary.prefix(AskOnPagePrompt.keptAnswerCharacters)) + "…")
        #expect(AskOnPagePrompt.dialogue(turns: [.init(question: "Summarize it", answer: summary)], question: "Who?").count < 900)
        let short = AskOnPagePrompt.conversation(url: "u", title: nil, date: "d", text: "page",
                                                 turns: [.init(question: "Who?", answer: "**Garry Conille**.")], question: "When?")
        #expect(short.earlier[0].response == "**Garry Conille**.")
    }

    @Test func followUpsKeepTheLastAnswersAndHideOlderOnes() {
        let turns = (1...3).map { AskOnPagePrompt.Turn(question: "q\($0)", answer: "a\($0)") }
        let c = AskOnPagePrompt.conversation(url: "u", title: nil, date: "d", text: "page", turns: turns, question: "q4")
        let page = AskOnPagePrompt.context(url: "u", title: nil, date: "d", text: "page")
        #expect(c.earlier == [
            .init(prompt: page + "q1", response: "[Older messages hidden]"),
            .init(prompt: "q2", response: "a2"),
            .init(prompt: "q3", response: "a3"),
        ])
        #expect(c.prompt == "q4" + AskOnPagePrompt.followUpReminder)
        #expect(AskOnPagePrompt.dialogue(turns: turns, question: "q4") == "q1\n[Older messages hidden]\nq2\na2\nq3\na3\nq4" + AskOnPagePrompt.followUpReminder)
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
        // On Apple's iOS page it wrote the question back as asked, without "Human:".
        #expect(AskOnPageReply.parts("How do reactions work?\n<excerpt>Reactions fill the frame.</excerpt>", question: "How do reactions work?")
                == [.init(text: "Reactions fill the frame.", isQuote: true)])
        // While it streams, the start of the question waits for the line to end.
        #expect(AskOnPageReply.parts("How do reac", question: "How do reactions work?") == [])
        #expect(AskOnPageReply.parts("Reactions are", question: "How do reactions work?") == [.init(text: "Reactions are", isQuote: false)])
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

    @Test func aStreamedAnswerReachesTheCardTenTimesASecond() {
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

    @Test func aStreamingAnswerIsDrawnLineByLine() {
        #expect(AskOnPageReply.lines("Key points:\n\n* one\n* two") == ["Key points:", " ", "* one", "* two"])
        #expect(AskOnPageReply.lines("one line") == ["one line"])
    }

    @Test func aLongAnswerEndsWhereTheContextDoes() {
        #expect(AskOnPagePrompt.responseTokens(contextTokens: 4096, promptTokens: 3400) == 696)
        #expect(AskOnPagePrompt.responseTokens(contextTokens: 4096, promptTokens: 5000) == 1)
        #expect(AskOnPagePrompt.responseTokens(contextTokens: 4096, promptTokens: nil) == nil)
        // An overflow after part of the answer keeps it; before any, the page is read shorter.
        #expect(AskOnPagePrompt.afterOverflow(streamed: "Here are the key points:\n* one") == .keepAnswer)
        #expect(AskOnPagePrompt.afterOverflow(streamed: " \n") == .readLess)
    }

    @Test func aQuoteThePageDoesntHaveIsCaughtBeforeFindOnPage() {
        let page = "Since 2020, Haiti's capital Port-au-Prince has been the site of an ongoing armed conflict.\nHenry ultimately resigned and was replaced by Garry Conille on 3 June 2024, who in turn was replaced."
        // On the page, despite case, curly quotes, a Markdown link, spacing or a cut-short second half.
        #expect(AskOnPageReply.isOnPage("Since 2020, Haiti’s capital   Port-au-Prince has been the site of an ongoing armed conflict.", pageText: page))
        #expect(AskOnPageReply.isOnPage("henry ultimately resigned and was replaced by [Garry Conille](https://x.org) on 3 June 2024", pageText: page))
        #expect(AskOnPageReply.isOnPage("Henry ultimately resigned and was replaced by Garry Conille. He later wrote a book.", pageText: page))
        // The live model's made-up quote on this page, and the test model's.
        #expect(!AskOnPageReply.isOnPage("Gangs were not the cause of El Salvador's success.", pageText: page))
        #expect(!AskOnPageReply.isOnPage(AskOnPagePrompt.fakeMadeUpQuote, pageText: page))
        #expect(!AskOnPageReply.isOnPage("  ", pageText: page))
    }

    @Test func theTestModelSummarizesAtLength() {
        let text = (1...30).map { "Sentence number \($0) about the page." }.joined(separator: " ")
        let answer = AskOnPagePrompt.fakeAnswer(question: "Summarize the key points of this article", text: text)
        #expect(answer.components(separatedBy: "\n* ").count - 1 == AskOnPagePrompt.fakeSummaryPoints)
        #expect(answer.hasPrefix("Here are the key points of the page:"))
        #expect(answer.count > 600)
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
}
