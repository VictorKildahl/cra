import CraCore
import Testing

struct AskOnPageRefusalTests {
    private let page = AskOnPagePrompt.Page(url: "https://example.com/news", title: "A senator's pitch",
        text: "Michigan Senator-elect Abdul El-Sayed has urged President Donald Trump to embrace Medicare for All.")

    /// GitHub #584: on a news article about a senator and the president, the on-device model refused the
    /// quoted answer ("May contain sensitive content") and the card said "Sorry, I encountered an error".
    /// The same question in plain text it answers ("Abdul El-Sayed"). A quoted or listed answer the model
    /// refuses is asked once more in plain text: the same page and question, plain instructions, no quotes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/584"))
    func aRefusedAnswerIsAskedAgainInPlainText() async throws {
        #expect(AskOnPage.Form.quoted.afterRefusal == .plain)
        #expect(AskOnPage.Form.summary.afterRefusal == .plain)
        #expect(AskOnPage.Form.plain.afterRefusal == nil)
        let count: AskOnPagePrompt.TokenCount = { ($0.utf8.count + $1.utf8.count + 3) / 4 }
        let quoted = try #require(await AskOnPagePrompt.fit(page: page, question: "who is being discussed in this article",
            language: "English", currentDate: "19 November 2026", countTokens: count))
        let plain = try #require(await AskOnPagePrompt.fit(page: page, question: "who is being discussed in this article",
            language: "English", currentDate: "19 November 2026", countTokens: count, form: quoted.form.afterRefusal))
        #expect(quoted.form == .quoted && plain.form == .plain)
        #expect(plain.prompt == quoted.prompt && plain.source == quoted.source)
        #expect(plain.instructions.contains("plain text") && !plain.instructions.contains("excerpts"))
        let answer = try #require(AskOnPage.completeAnswer(AskOnPage.plainDraft("  Abdul El-Sayed.\n"), source: plain.source))
        #expect(answer.text == "Abdul El-Sayed." && answer.quotes.isEmpty && answer.keyAnswer == nil && answer.isComplete)
    }

    /// An empty plain answer is no answer.
    @Test func anEmptyPlainAnswerIsNotComplete() {
        #expect(AskOnPage.completeAnswer(AskOnPage.plainDraft(" \n"), source: page.text) == nil)
    }
}
