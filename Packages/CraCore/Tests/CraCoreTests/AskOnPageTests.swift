import CraCore
import Testing

struct AskOnPageTests {
    @Test func quotesRequireTheTransmittedSourceAndKeepPunctuationAndCase() {
        let snapshot = "<excerpt>\nThe answer is **solar power**.\n</excerpt>\nMostly **solar power**."
        let valid = AskOnPage.answer(snapshot, source: "The answer is solar\n\t power.")
        #expect(valid.parts == [.quote(markdown: "The answer is **solar power**.", plainText: "The answer is solar power.", state: .verified),
                                .text("Mostly **solar power**.")])
        #expect(valid.hasVerifiedQuote)
        #expect(!AskOnPage.answer(snapshot, source: "The answer is Solar power.").hasVerifiedQuote)
        #expect(!AskOnPage.answer(snapshot, source: "The answer is solar power!").hasVerifiedQuote)
        // Text in the untransmitted rest of a page is not evidence for this turn.
        #expect(!AskOnPage.answer(snapshot, source: "This is only the page introduction.").hasVerifiedQuote)
    }

    @Test func markdownLinksAndCanonicalUnicodeUseTheVisibleQuoteText() {
        let answer = AskOnPage.answer("<excerpt>\n[Privacy Policy](https://example.com/privacy): Cafe\u{301}.\n</excerpt>",
                                      source: "Read our Privacy Policy: Café. It applies here.")
        #expect(answer.parts == [.quote(markdown: "[Privacy Policy](https://example.com/privacy): Cafe\u{301}.",
                                       plainText: "Privacy Policy: Cafe\u{301}.", state: .verified)])
    }

    @Test func cumulativeSnapshotsReplaceThePreviousParsedAnswer() {
        let beginning = "<excerpt>\nA supported sentence.\n</exc"
        let partial = AskOnPage.answer(beginning, source: "A supported sentence.")
        #expect(!partial.hasVerifiedQuote)
        #expect(partial.parts == [.quote(markdown: "A supported sentence.\n</exc", plainText: "A supported sentence.\n</exc", state: .incomplete)])
        let complete = AskOnPage.answer("<excerpt>\nA supported sentence.\n</excerpt>\n**Supported**.", source: "A supported sentence.")
        #expect(complete.parts.count == 2)
        #expect(complete.hasVerifiedQuote)
        #expect(AskOnPage.answer("<exc", source: "A supported sentence.").parts == [.text("<exc")])
    }

    @Test(arguments: [
        ("<excerpt>\n</excerpt>", AskOnPage.QuoteState.malformed),
        ("<excerpt>\n<excerpt>\nA fact.\n</excerpt>", .malformed),
        ("<excerpt>\nA fact.<excerpt>\n</excerpt>", .malformed),
        ("<excerpt>\nA fact.", .incomplete),
        ("<excerpt>\nAn invented fact.\n</excerpt>", .notFound),
    ])
    func malformedIncompleteAndInventedQuotesStayNonActionable(snapshot: String, state: AskOnPage.QuoteState) {
        let result = AskOnPage.answer(snapshot, source: "A fact.")
        #expect(!result.hasVerifiedQuote)
        guard case .quote(_, _, let actual) = result.parts.first else {
            Issue.record("Expected the quote to retain its explicit validation state")
            return
        }
        #expect(actual == state)
    }

    @Test func backgroundGuessesAndInlineTagsAreNotPageSupported() {
        let guess = "I think it’s **Brooklyn**, but it’s not mentioned on the page."
        #expect(AskOnPage.answer(guess, source: "The page discusses Manhattan.").parts == [.text(guess)])
        #expect(!AskOnPage.answer(guess, source: "The page discusses Manhattan.").hasVerifiedQuote)
        let inline = "Answer: <excerpt>A fact.</excerpt>"
        #expect(AskOnPage.answer(inline, source: "A fact.").parts == [.text(inline)])
    }

    @Test func multipleExcerptsRetainTheirOwnGroundingStates() {
        let response = "Introduction.\n<excerpt>\nA fact.\n</excerpt>\nAn answer.\n<excerpt>\nAn invention.\n</excerpt>"
        #expect(AskOnPage.answer(response, source: "A fact.").parts == [
            .text("Introduction."), .quote(markdown: "A fact.", plainText: "A fact.", state: .verified),
            .text("An answer."), .quote(markdown: "An invention.", plainText: "An invention.", state: .notFound),
        ])
    }

    @Test func responseBoundsCannotPromoteAnUnclosedExcerpt() {
        let huge = "<excerpt>\n" + String(repeating: "x", count: 70_000) + "\n</excerpt>"
        let result = AskOnPage.answer(huge, source: String(repeating: "x", count: 70_000))
        #expect(result.wasTruncated)
        #expect(!result.hasVerifiedQuote)
    }

    @Test func historyEvictsWholePairsAndRemembersTheOmission() {
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
