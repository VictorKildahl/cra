import CoreGraphics
import CraCore
import Foundation
import Testing

/// Settings ▸ Links ▸ Split View, Cra's own and off by default (GitHub #498): more than four panes in
/// a split, and a middle click on a link in a split's pane adding a pane.
struct SplitPaneOptionsTests {
    static let link = "https://example.com/next"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/498"))
    func aSplitHoldsArcsFourUnlessMorePanesIsOn() {
        #expect(SplitPaneLimit.maximum(morePanes: false) == 4)
        #expect(SplitPaneLimit.maximum(morePanes: true) == 8)
        #expect(SplitPaneLimit.canAdd(to: 3, morePanes: false))
        #expect(!SplitPaneLimit.canAdd(to: 4, morePanes: false), "Arc's four")
        #expect(SplitPaneLimit.canAdd(to: 4, morePanes: true))
        #expect(SplitPaneLimit.canAdd(to: 7, morePanes: true))
        #expect(!SplitPaneLimit.canAdd(to: 8, morePanes: true))
    }

    /// A tab dragged to a full split's edge opens no region at four, and does with the setting on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/498"))
    func aDropOnFourPanesOpensAFifthOnlyWithMorePanes() {
        let t = SplitDropProposalTests.self
        let ids = [t.a, t.b, t.c, t.d]
        let side = CGPoint(x: 990, y: 300)
        #expect(SplitDropProposal.propose(at: side, ids: ids, frames: t.four, orientation: .horizontal, area: t.area,
                                          region: nil, current: nil, sidebarSide: false) == nil)
        #expect(SplitDropProposal.propose(at: side, ids: ids, frames: t.four, orientation: .horizontal, area: t.area,
                                          region: nil, current: nil, sidebarSide: false,
                                          paneLimit: SplitPaneLimit.maximum(morePanes: true))
            == .insert(.init(index: 4, orientation: .horizontal)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/498"))
    func openInSplitViewTakesUpToTheLimit() {
        #expect(!PickedTabsMenu.isEnabled("openInSplitView", for: .init(count: 5)))
        #expect(PickedTabsMenu.isEnabled("openInSplitView", for: .init(count: 5, paneLimit: 8)))
        #expect(!PickedTabsMenu.isEnabled("openInSplitView", for: .init(count: 9, paneLimit: 8)))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/498"))
    func aMiddleClickInASplitAddsAPaneWhenTurnedOn() {
        func adds(_ url: String = SplitPaneOptionsTests.link, on: Bool = true, panes: Int = 2, limit: Int = 4, age: TimeInterval = 0.05,
                  modifiers: UInt = 0) -> Bool {
            LinkSplitClick.middleClickAddsPane(url, enabled: on, panes: panes, limit: limit, clickAge: age, modifiers: modifiers)
        }
        #expect(adds())
        #expect(adds(panes: 3))
        #expect(!adds(on: false), "off: a tab behind the page, as in Arc")
        #expect(!adds(panes: 1), "not in a split: a tab behind the page")
        #expect(!adds(panes: 4), "a full split: the link still opens, as a tab")
        #expect(adds(panes: 4, limit: 8), "more panes on")
        #expect(!adds(age: -1), "no middle click in this page: a ⌘-click")
        #expect(!adds(age: LinkSplitClick.freshness + 0.01), "a middle click long ago")
        #expect(!adds(modifiers: KeyChord.Modifiers.command.rawValue), "⌘ held: the ⌘-click's background tab")
        #expect(!adds(modifiers: KeyChord.Modifiers.shift.rawValue), "⇧ held: a front tab")
        #expect(adds(modifiers: 1 << 16), "Caps Lock (AppKit's alphaShift) doesn't count")
        #expect(!adds("file:///Users/me/page.html"), "web addresses only")
        #expect(!adds("mailto:me@example.com"))
    }

    /// Off unless turned on, for new settings and ones saved before they existed; kept once on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/498"))
    func offByDefault() throws {
        let decoder = ModelFixtureTests.decoder
        let old = try decoder.decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!AppSettings().splitMorePanes && !old.splitMorePanes)
        #expect(!AppSettings().splitMiddleClickAddsPane && !old.splitMiddleClickAddsPane)
        var on = AppSettings()
        on.splitMorePanes = true
        on.splitMiddleClickAddsPane = true
        let saved = try decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(on))
        #expect(saved.splitMorePanes && saved.splitMiddleClickAddsPane)
    }
}
