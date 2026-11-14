import CraCore
import Foundation
import Testing

struct PageInfoBarTests {
    /// The debugger bar as the engine reports it: a message, Cancel and a ✕ (GitHub #241).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/241"))
    func decodesTheDebuggerBar() {
        let entry: [String: Any] = ["id": NSNumber(value: 4_377_000), "message": "“Playwright” started debugging this browser",
                                    "cancel": "Cancel", "closeable": NSNumber(value: true)]
        let bar = PageInfoBar(entry)
        #expect(bar == PageInfoBar(id: 4_377_000, message: "“Playwright” started debugging this browser", cancel: "Cancel"))
        #expect(PageInfoBar.inset(for: [bar!]) == 40)
        #expect(PageInfoBar.inset(for: []) == 0)
    }

    @Test func refusesBarsWithoutIdOrMessageAndDropsEmptyTitles() {
        #expect(PageInfoBar(["message": "x"]) == nil)
        #expect(PageInfoBar(["id": 1, "message": ""]) == nil)
        let bar = PageInfoBar(["id": 2, "message": "Allow?", "ok": "Allow", "cancel": "", "link": "", "closeable": false])
        #expect(bar?.ok == "Allow" && bar?.cancel == nil && bar?.link == nil && bar?.closeable == false)
    }
}
