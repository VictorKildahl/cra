import CraCore
import Testing

/// The links Arc peeked from a pinned tab (docs/arc-reverse-engineering.md, "Peek and the copy
/// toast's Share button"), on the lab page at 127.0.0.1.
struct PeekTriggerTests {
    static let page = "http://127.0.0.1:8765/lab.html"
    static let other = "http://localhost:8765/other.html"
    static let same = "http://127.0.0.1:8765/same.html"

    static func opens(_ url: String, shift: Bool = false, newTab: Bool = false, pinned: Bool = true,
                      _ change: (inout AppSettings) -> Void = { _ in }) -> Bool {
        var s = AppSettings()
        change(&s)
        return PeekTrigger.opens(url, from: page, shiftClick: shift, newTab: newTab, fromPinned: pinned, settings: s)
    }

    @Test func pinnedTabPeeksAtOtherHosts() {
        #expect(Self.opens(Self.other))
        #expect(Self.opens(Self.other, newTab: true))
        #expect(!Self.opens(Self.same))
    }

    @Test func aNewTabLinkPeeksEvenOnTheSameHost() {
        #expect(Self.opens(Self.same, newTab: true))
    }

    @Test func todayTabsLoadUnlessEveryTabIsOn() {
        #expect(!Self.opens(Self.other, pinned: false))
        #expect(!Self.opens(Self.same, newTab: true, pinned: false))
        #expect(Self.opens(Self.other, pinned: false) { $0.peekInEveryTab = true })
    }

    @Test func shiftClickPeeksFromAnyTab() {
        #expect(Self.opens(Self.same, shift: true, pinned: false))
        #expect(!Self.opens(Self.same, shift: true) { $0.peekOnShiftClick = false })
    }

    @Test func settingsAndSchemes() {
        #expect(!Self.opens(Self.other) { $0.peekLinksToOtherSites = false })
        #expect(!Self.opens("file:///tmp/a.html", newTab: true))
        #expect(!Self.opens("cra://settings", shift: true))
    }

    /// Inside the Peek (GitHub #202).
    @Test func aNewTabLinkInsideThePeekLeavesIt() {
        #expect(PeekTrigger.leavesPeek(Self.other, shiftClick: false, newTab: true))
        #expect(PeekTrigger.leavesPeek(Self.same, shiftClick: false, newTab: true))
        #expect(PeekTrigger.leavesPeek("HTTPS://example.org/", shiftClick: false, newTab: true))
        #expect(PeekTrigger.leavesPeek("file:///tmp/a.html", shiftClick: false, newTab: true))
        // A plain link loads in the Peek, and so does a Shift-click.
        #expect(!PeekTrigger.leavesPeek(Self.other, shiftClick: false, newTab: false))
        #expect(!PeekTrigger.leavesPeek(Self.other, shiftClick: true, newTab: false))
        // Pages a tab can't take without the opener, or that a page must not open.
        #expect(!PeekTrigger.leavesPeek("about:blank", shiftClick: false, newTab: true))
        #expect(!PeekTrigger.leavesPeek("", shiftClick: false, newTab: true))
        #expect(!PeekTrigger.leavesPeek("cra://settings", shiftClick: false, newTab: true))
        #expect(!PeekTrigger.leavesPeek("javascript:alert(1)", shiftClick: false, newTab: true))
    }
}
