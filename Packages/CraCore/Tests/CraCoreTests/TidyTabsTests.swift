import CraCore
import Foundation
import Testing

/// Arc's Tidy Tabs with the Mac's own model: what the sidebar makes of the model's answer.
struct TidyTabsTests {
    @Test func offeredFromSixTodayTabsUntilTidied() {
        let six = ["a", "b", "c", "d", "e", "f"]
        #expect(TidyTabs.offers(todayTabs: 6, looseTabs: six, tidied: nil))
        #expect(!TidyTabs.offers(todayTabs: 5, looseTabs: Array(six.prefix(5)), tidied: nil))
        // Grouped tabs count (Arc: two loose and six grouped offered Tidy); nothing loose, nothing to do.
        #expect(TidyTabs.offers(todayTabs: 8, looseTabs: ["a", "b"], tidied: nil))
        #expect(!TidyTabs.offers(todayTabs: 8, looseTabs: [String](), tidied: nil))
        // After a run (even one that grouped nothing) the tabs it saw don't bring it back…
        #expect(!TidyTabs.offers(todayTabs: 6, looseTabs: six.reversed(), tidied: Set(six)))
        #expect(!TidyTabs.offers(todayTabs: 6, looseTabs: ["a"], tidied: Set(six)))
        // …a new tab does.
        #expect(TidyTabs.offers(todayTabs: 7, looseTabs: ["a", "g"], tidied: Set(six)))
    }

    @Test func promptListsTabsWithIdsAndExistingGroups() {
        let p = TidyTabs.prompt(tabs: [.init(title: "Mars - Wikipedia", host: "en.wikipedia.org"),
                                       .init(title: "", host: "example.com"),
                                       .init(title: "Line one\nline two", host: "")],
                                existingGroups: ["Bread"])
        #expect(p == """
        Here are my tabs, as 'id: title (site)':
        0: Mars - Wikipedia (en.wikipedia.org)
        1: example.com (example.com)
        2: Line one line two

        I already have these groups; reuse a name exactly to add tabs to it: "Bread".
        """)
    }

    @Test func promptCutsLongTitlesAndTabLists() {
        let tabs = Array(repeating: TidyTabs.Tab(title: String(repeating: "x", count: 200), host: "h"), count: 100)
        let lines = TidyTabs.prompt(tabs: tabs, existingGroups: []).split(separator: "\n")
        #expect(lines.count == TidyTabs.maximumTabs + 1)
        #expect(lines[1] == "0: " + String(repeating: "x", count: 79) + "… (h)")
    }

    @Test func planDropsBadIdsDuplicatesAndOneTabGroups() {
        let plan = TidyTabs.plan([.init(name: "Planets", tabs: [6, 0, 3, 99, -1]),
                                  .init(name: "Bread", tabs: [1, 4, 7, 0]),
                                  .init(name: "Email", tabs: [8]),
                                  .init(name: "  ", tabs: [2, 5])],
                                 tabCount: 9, existingGroups: [])
        #expect(plan.newGroups == [.init(name: "Planets", tabs: [0, 3, 6]), .init(name: "Bread", tabs: [1, 4, 7])])
        #expect(plan.joins.isEmpty)
    }

    @Test func planMergesSameNamesAndJoinsExistingGroups() {
        let planets = TidyTabs.ExistingGroup(id: UUID(), name: "Planets")
        let bread = TidyTabs.ExistingGroup(id: UUID(), name: "Bread")
        let plan = TidyTabs.plan([.init(name: "Python", tabs: [4]),
                                  .init(name: "bread.", tabs: [0]),
                                  .init(name: "python", tabs: [2]),
                                  .init(name: "Travel", tabs: [3, 1])],
                                 tabCount: 5, existingGroups: [planets, bread])
        #expect(plan.joins == [bread.id: [0]])
        // New groups follow their first tab's place.
        #expect(plan.newGroups == [.init(name: "Travel", tabs: [1, 3]), .init(name: "Python", tabs: [2, 4])])
    }

    @Test func duplicateExistingNamesKeepTheFirstOriginalIdentity() {
        let first = TidyTabs.ExistingGroup(id: UUID(), name: "Bréad")
        let duplicate = TidyTabs.ExistingGroup(id: UUID(), name: "BREAD")
        let plan = TidyTabs.plan([.init(name: "bread", tabs: [0])], tabCount: 1, existingGroups: [first, duplicate])
        #expect(plan.joins == [first.id: [0]])
        #expect(plan.newGroups.isEmpty)
    }

    @Test func planCapsNames() {
        let plan = TidyTabs.plan([.init(name: String(repeating: "n", count: 50), tabs: [0, 1])], tabCount: 2, existingGroups: [])
        #expect(plan.newGroups.first?.name.count == 32)
        #expect(TidyTabs.plan([], tabCount: 3, existingGroups: []).isEmpty)
    }

    @Test func orderKeepsLooseTabsAboveTheGroups() {
        let today = ["t1", "G", "t2", "t3", "t4"]
        let order = TidyTabs.order(today: today, isGroup: { $0.hasPrefix("G") || $0.hasPrefix("N") },
                                   grouped: ["t2", "t4"], newGroups: ["N1", "N2"])
        #expect(order == ["t1", "t3", "G", "N1", "N2"])
    }
}

/// A tab group is a folder with a mark, so a Cra from before groups still reads the file.
struct TabGroupItemTests {
    @Test func groupRoundTripsAndPlainFoldersWriteNoMark() throws {
        let group = SidebarItem.tabGroup("Planets", parent: nil)
        #expect(group.isFolder && group.isTabGroup && group.title == "Planets")
        let data = try JSONEncoder().encode(group)
        #expect(try JSONDecoder().decode(SidebarItem.self, from: data) == group)
        let folder = try JSONEncoder().encode(SidebarItem.folder("F", parent: nil))
        #expect(!String(decoding: folder, as: UTF8.self).contains("tabGroup"))
        #expect(try !JSONDecoder().decode(SidebarItem.self, from: folder).isTabGroup)
    }
}
