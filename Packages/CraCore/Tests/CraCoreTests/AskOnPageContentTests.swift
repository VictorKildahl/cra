import CraCore
import Foundation
import Testing

struct AskOnPageContentTests {
    private let url = "https://example.com/article"
    private let text = "The source article contains a complete sentence that the model can quote directly."

    private func evaluation(url: String? = nil, text: String? = nil, contentType: String = "text/html", truncated: Any = false) throws -> String {
        let value: [String: Any] = ["url": url ?? self.url, "title": "Article", "text": text ?? self.text,
                                    "contentType": contentType, "truncated": truncated]
        return String(data: try JSONSerialization.data(withJSONObject: ["result": ["value": value]]), encoding: .utf8)!
    }

    @Test func snapshotRequiresTheExactDocumentAndReadableHTML() throws {
        let result = try evaluation()
        let page = try #require(AskOnPageContent.page(evaluation: result, expectedURL: url))
        #expect(page.text == text && page.title == "Article" && !page.wasTruncated)
        #expect(AskOnPageContent.page(evaluation: result, expectedURL: url + "#later") == nil)
        for mime in ["application/pdf", "image/png", "image/svg+xml", "video/mp4", "text/plain"] {
            #expect(AskOnPageContent.page(evaluation: try evaluation(contentType: mime), expectedURL: url) == nil)
        }
        #expect(AskOnPageContent.page(evaluation: try evaluation(contentType: "application/xhtml+xml"), expectedURL: url)?.text == text)
        #expect(AskOnPageContent.page(evaluation: try evaluation(text: "Just a short heading"), expectedURL: url) == nil)
        #expect(AskOnPageContent.page(evaluation: try evaluation(url: "cra://settings"), expectedURL: "cra://settings") == nil)
        #expect(AskOnPageContent.page(evaluation: try evaluation(url: "file:///tmp/article.html"), expectedURL: "file:///tmp/article.html") == nil)
    }

    @Test func extractionBoundsAndTruncationAreNotSilentlyDiscarded() throws {
        #expect(AskOnPageContent.page(evaluation: try evaluation(truncated: true), expectedURL: url)?.wasTruncated == true)
        #expect(AskOnPageContent.page(evaluation: try evaluation(text: String(repeating: "x", count: 65_537)), expectedURL: url) == nil)
        #expect(AskOnPageContent.page(evaluation: try evaluation(truncated: 1), expectedURL: url) == nil)
        #expect(AskOnPageContent.page(evaluation: String(repeating: " ", count: 300_001), expectedURL: url) == nil)
    }

    @Test(arguments: [nil, "{}", "not JSON", #"{"result":{"value":null}}"#, #"{"result":{}}"#,
                       #"{"result":{"value":{}},"exceptionDetails":{}}"#])
    func invalidOrExceptionalEvaluationsNeverBecomeContext(result: String?) {
        #expect(AskOnPageContent.page(evaluation: result, expectedURL: url) == nil)
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/393"))
    func quoteResultsRequireCompletedBoundedDOMEvidence() throws {
        let hit = #"{"result":{"value":{"found":true,"startNode":0,"startOffset":2,"endNode":1,"endOffset":4}}}"#
        guard case .match = AskOnPageQuoteDOM.result(hit) else { Issue.record("a complete exact range must decode"); return }
        #expect(AskOnPageQuoteDOM.result(#"{"result":{"value":{"found":false}}}"#) == .notFound)
        #expect(AskOnPageQuoteDOM.effected(#"{"result":{"value":{"found":true}}}"#) == true)
        for bad in [nil, "{}", #"{"result":{"value":{"found":true}}}"#,
                    hit.replacingOccurrences(of: "\"startNode\":0", with: "\"startNode\":-1"),
                    hit.replacingOccurrences(of: "\"endOffset\":4", with: "\"endOffset\":65537"),
                    #"{"result":{"value":{"found":true}},"exceptionDetails":{}}"#] {
            #expect(AskOnPageQuoteDOM.result(bad) == nil)
        }
        #expect(AskOnPageQuoteDOM.effected(#"{"result":{"value":{"count":7}}}"#) == nil)
        #expect(AskOnPageQuoteDOM.effected(#"{"result":{"value":{"found":1}}}"#) == nil)
        #expect(AskOnPageQuoteDOM.effected(#"{"result":{"value":{"found":true}},"exceptionDetails":{}}"#) == nil)
    }

}
