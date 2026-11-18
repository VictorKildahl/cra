import CraCore
import Foundation
import Testing

/// Settings ▸ Links ▸ "Open background tabs below the current tab" (GitHub #532): a link's tab goes
/// right below the tab it came from in Today, after the ones that tab opened before.
struct LinkTabPlacementTests {
    /// A small sidebar: Today with tabs, a folder and a split, and Pinned with one tab.
    struct Sidebar {
        var items: [UUID: SidebarItem] = [:]
        let today: UUID, pinned: UUID

        init() {
            let space = UUID()
            let t = SidebarItem.container(.today(spaceID: space)), p = SidebarItem.container(.pinned(spaceID: space))
            today = t.id
            pinned = p.id
            items[t.id] = t
            items[p.id] = p
        }

        @discardableResult
        mutating func add(_ item: SidebarItem) -> UUID {
            items[item.id] = item
            if let p = item.parentID { items[p]!.children.append(item.id) }
            return item.id
        }

        @discardableResult
        mutating func tab(_ url: String, in parent: UUID, from referrer: UUID? = nil) -> UUID {
            var t = SidebarItem.tab(url, parent: parent)
            if case .tab(var d) = t.data { d.referrerID = referrer; t.data = .tab(d) }
            return add(t)
        }

        func slot(below source: UUID, afterEarlierLinks: Bool = true) -> LinkTabPlacement.Slot? {
            LinkTabPlacement.belowSource(source, afterEarlierLinks: afterEarlierLinks) { items[$0] }
        }
    }

    /// Off unless turned on, for new settings and ones saved before the key existed; kept once on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func theSettingIsOffByDefault() throws {
        let old = try ModelFixtureTests.decoder.decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!AppSettings().backgroundTabsBelowCurrent && !old.backgroundTabsBelowCurrent)
        var on = AppSettings()
        on.backgroundTabsBelowCurrent = true
        let saved = try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(on))
        #expect(saved.backgroundTabsBelowCurrent)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func aTodayTabsLinkGoesRightBelowIt() {
        var s = Sidebar()
        s.tab("https://a.com", in: s.today)
        let source = s.tab("https://b.com", in: s.today)
        s.tab("https://c.com", in: s.today)
        #expect(s.slot(below: source) == .init(parent: s.today, index: 2))
    }

    /// Three ⌘-clicks read top to bottom in the order they were clicked, and a tab the source didn't
    /// open ends the run.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func laterLinksGoAfterTheOnesTheSourceOpenedBefore() {
        var s = Sidebar()
        let source = s.tab("https://source.com", in: s.today)
        s.tab("https://one.com", in: s.today, from: source)
        s.tab("https://two.com", in: s.today, from: source)
        let other = s.tab("https://other.com", in: s.today)
        s.tab("https://three.com", in: s.today, from: source)
        #expect(s.slot(below: source) == .init(parent: s.today, index: 3))
        #expect(s.slot(below: source, afterEarlierLinks: false) == .init(parent: s.today, index: 1),
                "Open Link in New Tab, as before #532: straight under the source")
        #expect(s.slot(below: other) == .init(parent: s.today, index: 4))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func aTabInAFolderGetsItsSlotInTheFolder() {
        var s = Sidebar()
        s.tab("https://a.com", in: s.today)
        let folder = s.add(.folder("Work", parent: s.today))
        s.tab("https://x.com", in: folder)
        let source = s.tab("https://y.com", in: folder)
        #expect(s.slot(below: source) == .init(parent: folder, index: 2))
    }

    /// A pane's link never becomes a pane: it goes below the split in Today. Before, "Open Link in New
    /// Tab" from a pane put the tab into the split.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func aSplitPanesLinkGoesBelowTheSplit() {
        var s = Sidebar()
        s.tab("https://a.com", in: s.today)
        let split = s.add(.split(parent: s.today))
        s.tab("https://left.com", in: split)
        let pane = s.tab("https://right.com", in: split)
        s.tab("https://c.com", in: s.today)
        #expect(s.slot(below: pane) == .init(parent: s.today, index: 2))
        #expect(s.slot(below: pane, afterEarlierLinks: false) == .init(parent: s.today, index: 2))
    }

    /// Pinned tabs, favorites and live folders keep no slot: their links open where new tabs go.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/532"))
    func outsideTodayThereIsNoSlot() {
        var s = Sidebar()
        let pinnedTab = s.tab("https://pinned.com", in: s.pinned)
        #expect(s.slot(below: pinnedTab) == nil)
        var live = SidebarItem.folder("PRs", parent: s.today)
        live.liveFolder = LiveFolderData()
        let liveID = s.add(live)
        let fed = s.tab("https://github.com/pr/1", in: liveID)
        #expect(s.slot(below: fed) == nil)
        #expect(s.slot(below: UUID()) == nil, "a source tab that's gone")
        #expect(s.slot(below: s.today) == nil, "only a tab is a source")
    }
}
