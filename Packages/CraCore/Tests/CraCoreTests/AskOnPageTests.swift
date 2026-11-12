import CraCore
import Foundation
import Testing

struct AskOnPageTests {
    @Test func quotesRequireTheExactTransmittedSource() throws {
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

    @Test func partialFieldsNeverEnableEvidence() {
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
