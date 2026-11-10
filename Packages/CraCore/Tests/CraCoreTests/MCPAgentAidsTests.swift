import CraCore
import Foundation
import Testing

struct MCPAgentAidsTests {
    typealias E = MCPChanges.Element

    @Test func changesByRef() {
        let before = [E(ref: "e1", role: "button", name: "Add"), E(ref: "e2", role: "checkbox", name: "Done", state: "checked=false"),
                      E(ref: "e3", role: "link", name: "Old")]
        let after = [E(ref: "e1", role: "button", name: "Add"), E(ref: "e2", role: "checkbox", name: "Done", state: "checked=true"),
                     E(ref: "e4", role: "textbox", name: "Title")]
        let diff = MCPChanges.diff(before: before, after: after)
        #expect(diff["added"] as? [String] == ["textbox \"Title\" e4"])
        #expect(diff["changed"] as? [String] == ["checkbox \"Done\" [checked=true] e2 (was [checked=false])"])
        #expect(diff["removed"] as? [String] == ["link \"Old\" e3"])
        #expect(MCPChanges.diff(before: before, after: before).isEmpty)
    }

    @Test func longRunsFold() {
        let options = (0..<48).map { E(ref: "o\($0)", role: "option", name: "Item \($0)", state: $0 == 3 ? "selected=true" : "") }
        let added = MCPChanges.diff(before: [], after: [E(ref: "b", role: "button", name: "Open")] + options)["added"] as? [String]
        #expect(added == ["button \"Open\" b", "48 option: Item 0 … Item 47 (o0 … o47)", "option \"Item 3\" [selected=true] o3"])
        let many = (0..<60).map { E(ref: "x\($0)", role: $0 % 2 == 0 ? "button" : "link", name: "\($0)") }
        let capped = MCPChanges.diff(before: [], after: many, limit: 40)["added"] as? [String]
        #expect(capped?.count == 41 && capped?.last?.hasPrefix("… 20 more") == true)
        let removed = MCPChanges.diff(before: many, after: [])["removed"] as? [String]
        #expect(removed?.first == "60 elements" && removed?.count == 4)
    }

    @Test func redactedURLs() {
        #expect(MCPRedaction.url("https://user:pw@api.example.com/v1/items?id=42&token=abc#frag") == "https://api.example.com/v1/items?id=42&token=…")
        #expect(MCPRedaction.url("https://x.example/cb?code=1&state=2&page=3") == "https://x.example/cb?code=…&state=…&page=3")
        #expect(MCPRedaction.url("https://x.example/reset/a1b2c3d4e5f6g7h8i9j0k1/done") == "https://x.example/reset/…/done")
        #expect(MCPRedaction.url("https://x.example/p?a%20b=1") == "https://x.example/p?…=…")
        #expect(MCPRedaction.url("data:text/plain,secret") == "data:…")
        #expect(MCPRedaction.url("not a url") == "…")
    }

    @Test func typedFieldValues() {
        #expect(MCPFieldValue.normalized(type: "date", value: "2026-11-09") == "2026-11-09")
        #expect(MCPFieldValue.normalized(type: "date", value: "2026-02-30") == nil)
        #expect(MCPFieldValue.normalized(type: "date", value: "09/11/2026") == nil)
        #expect(MCPFieldValue.normalized(type: "time", value: "2:30 PM") == "14:30")
        #expect(MCPFieldValue.normalized(type: "time", value: "12:05 am") == "00:05")
        #expect(MCPFieldValue.normalized(type: "time", value: "09:07:03.250") == "09:07:03.250")
        #expect(MCPFieldValue.normalized(type: "time", value: "24:00") == nil)
        #expect(MCPFieldValue.normalized(type: "datetime-local", value: "2026-11-09 2:30 PM") == "2026-11-09T14:30")
        #expect(MCPFieldValue.normalized(type: "month", value: "2026-13") == nil)
        #expect(MCPFieldValue.normalized(type: "week", value: "2026-w07") == "2026-W07")
        #expect(MCPFieldValue.normalized(type: "color", value: "#3B82F6") == "#3b82f6")
        #expect(MCPFieldValue.normalized(type: "color", value: "f0a") == "#ff00aa")
        #expect(MCPFieldValue.normalized(type: "color", value: "red") == nil)
        #expect(MCPFieldValue.normalized(type: "range", value: "42.5") == "42.5")
        #expect(MCPFieldValue.normalized(type: "range", value: "lots") == nil)
        #expect(MCPFieldValue.normalized(type: "date", value: "") == "")
    }

    @Test func siteKeys() {
        #expect(MCPSiteNotes.site("https://Mail.Google.com:443/u/0") == "mail.google.com")
        #expect(MCPSiteNotes.site("mail.google.com") == "mail.google.com")
        #expect(MCPSiteNotes.site("http://127.0.0.1:8792/x") == "127.0.0.1:8792")
        #expect(MCPSiteNotes.site("localhost:3000") == "localhost:3000")
        for bad in ["../../etc/passwd", "file:///etc/hosts", "a/b", "", "chrome://settings", "exa mple.com"] { #expect(MCPSiteNotes.site(bad) == nil) }
        #expect(MCPSiteNotes.fileName("127.0.0.1:8792") == "127.0.0.1_8792.md")
    }

    @Test func historyNewestFirstWithAllWords() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let entries = [HistoryEntry(url: "https://github.com/VictorKildahl/cra/issues", title: "Issues · cra", lastVisit: now.addingTimeInterval(-60), visitCount: 3),
                       HistoryEntry(url: "https://github.com/VictorKildahl/cra", title: "cra", lastVisit: now.addingTimeInterval(-10), visitCount: 9),
                       HistoryEntry(url: "https://old.example/cra", title: "Old", lastVisit: now.addingTimeInterval(-90 * 86400), visitCount: 1),
                       HistoryEntry(url: "file:///Users/x/cra.txt", title: "cra", lastVisit: now, visitCount: 1)]
        let since = now.addingTimeInterval(-7 * 86400)
        #expect(MCPHistory.search(entries, query: "CRA", since: since, limit: 10).map(\.title) == ["cra", "Issues · cra"])
        #expect(MCPHistory.search(entries, query: "cra issues", since: since, limit: 10).map(\.title) == ["Issues · cra"])
        #expect(MCPHistory.search(entries, query: nil, since: since, limit: 1).map(\.title) == ["cra"])
    }
}
