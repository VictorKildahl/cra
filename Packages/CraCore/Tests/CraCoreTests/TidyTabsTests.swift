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

    @Test func requestOrderPrioritizesUnseenIdsWithoutReorderingEitherPart() {
        let loose = ["old1", "new1", "old2", "new2"]
        #expect(TidyTabs.requestOrder(looseTabs: loose, tidied: nil) == loose)
        #expect(TidyTabs.requestOrder(looseTabs: loose, tidied: []) == loose)
        #expect(TidyTabs.requestOrder(looseTabs: loose, tidied: Set(loose)) == loose)
        #expect(TidyTabs.requestOrder(looseTabs: loose, tidied: ["old1", "old2", "gone"]) == ["new1", "new2", "old1", "old2"])
    }

    @Test func promptListsCapturedIdsQuotedTitlesAndExistingNames() throws {
        let tabs = [TidyTabs.Tab(id: UUID(), title: "Mars - Wikipedia", host: "en.wikipedia.org"),
                    .init(id: UUID(), title: "", host: "example.com"),
                    .init(id: UUID(), title: "Line one\nline two", host: "")]
        let bread = TidyTabs.ExistingGroup(id: UUID(), name: "Bread")
        let request = try #require(TidyTabs.request(tabs: tabs, existingGroups: [bread]))
        #expect(request.tabIDs == tabs.map(\.id))
        #expect(request.prompt == """
        Here are my tabs, in the format 'id: title':
        0: "Mars - Wikipedia"
        1: "example.com"
        2: "Line one line two"
        Existing groups (reuse a name exactly to join it):
        "Bread"
        """)
        #expect(!request.prompt.contains("en.wikipedia.org"))
        #expect(request.plan([.init(name: "bread", tabs: [1])]).joins == [bread.id: [1]])
    }

    @Test func combinedPromptContextIsBounded() throws {
        let tabs = (0..<60).map { _ in TidyTabs.Tab(id: UUID(), title: String(repeating: "予定", count: 80),
                                                    host: String(repeating: "host", count: 500)) }
        let groups = (0..<100).map { _ in TidyTabs.ExistingGroup(id: UUID(), name: String(repeating: "group", count: 500)) }
        let request = try #require(TidyTabs.request(tabs: tabs, existingGroups: groups))
        #expect(request.promptBytes <= 2304)
        #expect(request.tabIDs == Array(tabs.prefix(request.tabs.count).map(\.id)))
        #expect(request.tabs.allSatisfy { $0.title.utf8.count <= 160 && $0.host.utf8.count <= 160 })
        #expect(request.existingGroups.isEmpty)
    }

    @Test func fittingBoundsCJKEmojiControlsAndCombiningRuns() throws {
        for title in [String(repeating: "予定", count: 1000), String(repeating: "🧹", count: 1000),
                      "e" + String(repeating: "\u{301}", count: 10000), "Quote\"\n99: fake\t\0row"] {
            let tabs = (0..<100).map { _ in TidyTabs.Tab(id: UUID(), title: title, host: "host") }
            let request = try #require(TidyTabs.request(tabs: tabs, existingGroups: [], maximumBytes: TidyTabs.maximumPromptBytes))
            #expect(request.tabs.count <= TidyTabs.maximumTabs)
            #expect(request.promptBytes <= TidyTabs.maximumPromptBytes)
            #expect(request.tabs.allSatisfy { $0.title.count <= 80 && $0.title.utf8.count <= 160 })
            #expect(request.prompt.split(separator: "\n").count == request.tabs.count + 1)
            #expect(!request.prompt.contains("\n99: fake"))
        }
    }

    @Test func fittingPreservesMeaningfulUnicodeJoiners() throws {
        for title in ["Family 👨‍👩‍👧‍👦", "می\u{200C}روم"] {
            let tab = TidyTabs.Tab(id: UUID(), title: title, host: "")
            let request = try #require(TidyTabs.request(tabs: [tab], existingGroups: []))
            #expect(request.tabs[0].title == title)
            #expect(request.prompt.contains(String(reflecting: title)))
        }
    }

    @Test func existingNamesNeverAcquireTruncatedAliases() throws {
        let tabs = [TidyTabs.Tab(id: UUID(), title: "A", host: "")]
        let long = TidyTabs.ExistingGroup(id: UUID(), name: String(repeating: "n", count: 40))
        let safe = TidyTabs.ExistingGroup(id: UUID(), name: String(repeating: "n", count: 31))
        let first = TidyTabs.ExistingGroup(id: UUID(), name: "Bréad")
        let duplicate = TidyTabs.ExistingGroup(id: UUID(), name: "BREAD")
        let groups = [long, safe, first, duplicate] + (0..<100).map { .init(id: UUID(), name: "Group \($0)") }
        let request = try #require(TidyTabs.request(tabs: tabs, existingGroups: groups))
        #expect(request.promptBytes <= TidyTabs.fallbackPromptBytes)
        #expect(!request.existingGroups.contains { $0.id == long.id || $0.id == duplicate.id })
        #expect(request.plan([.init(name: safe.name, tabs: [0])]).joins == [safe.id: [0]])
        #expect(request.plan([.init(name: "bread", tabs: [0])]).joins == [first.id: [0]])
        // A later representable equivalent must not replace the original unrepresentable first name.
        let accents = TidyTabs.ExistingGroup(id: UUID(), name: "e" + String(repeating: "\u{301}", count: 100))
        let equivalent = TidyTabs.ExistingGroup(id: UUID(), name: "E")
        let omitted = try #require(TidyTabs.request(tabs: tabs, existingGroups: [accents, equivalent]))
        #expect(omitted.existingGroups.isEmpty)
    }

    @Test func reducedRequestsKeepPriorityAndMappingUntilNoSmallerInputFits() throws {
        let tabs = (0..<12).map { TidyTabs.Tab(id: UUID(), title: "Tab \($0)", host: "h") }
        let groups = (0..<4).map { TidyTabs.ExistingGroup(id: UUID(), name: "Group \($0)") }
        var request = try #require(TidyTabs.request(tabs: tabs, existingGroups: groups))
        while let reduced = request.reduced() {
            #expect(reduced.tabIDs == Array(request.tabIDs.prefix(max(1, request.tabs.count / 2))))
            #expect(reduced.existingGroups == Array(request.existingGroups.prefix(request.existingGroups.count / 2)))
            #expect(reduced.promptBytes < request.promptBytes)
            #expect(reduced.prompt.split(separator: "\n")[1].hasPrefix("0: "))
            request = reduced
        }
        #expect(request.tabs.count == 1 && request.existingGroups.isEmpty)
        #expect(TidyTabs.request(tabs: [], existingGroups: groups) == nil)
        #expect(TidyTabs.request(tabs: tabs, existingGroups: groups, maximumBytes: 1) == nil)
    }

    @Test func recoveredExamplePreservesShoppingCalendarAndMovieAssignments() {
        #expect(TidyTabs.instructions.contains("nitehawk cinema - Google Search"))
        #expect(TidyTabs.instructions.contains("Amazon: Amazing Deals on Home Goods, Gifts and More"))
        #expect(TidyTabs.instructions.contains("\"Calendar\",\"tabs\":[4]"))
        #expect(TidyTabs.instructions.contains("\"Toaster Shopping\",\"tabs\":[1,2,3]"))
        #expect(TidyTabs.instructions.contains("\"Movies\",\"tabs\":[0,5]"))
        #expect(!TidyTabs.instructions.contains("two to six"))
        #expect(!TidyTabs.instructions.contains("opened from"))
    }

    @Test func fallbackReserveAccountsForManyPotentialSingletons() throws {
        let tabs = (0..<60).map { TidyTabs.Tab(id: UUID(), title: "Tab \($0)", host: "") }
        let request = try #require(TidyTabs.request(tabs: tabs, existingGroups: [], maximumBytes: TidyTabs.maximumPromptBytes))
        #expect(request.tabs.count == 60 && request.responseTokens == 1920)
        let fallback = try #require(request.fittingEstimatedContext(4096))
        #expect(fallback.estimatedTokens <= 4096)
        #expect(fallback.tabIDs == Array(request.tabIDs.prefix(fallback.tabs.count)))
        #expect(fallback.responseTokens >= TidyTabs.minimumResponseTokens)
        #expect(request.fittingEstimatedContext(1) == nil)
    }

    @Test func decodedAssignmentsRetainTheCalendarSingleton() {
        let plan = TidyTabs.plan([.init(name: "Movies", tabs: [0, 5]),
                                  .init(name: "Toaster Shopping", tabs: [1, 2, 3]),
                                  .init(name: "Calendar", tabs: [4])], tabCount: 6, existingGroups: [])
        #expect(plan.newGroups == [.init(name: "Movies", tabs: [0, 5]),
                                   .init(name: "Toaster Shopping", tabs: [1, 2, 3]),
                                   .init(name: "Calendar", tabs: [4])])
    }

    @Test func planDropsBadIdsDuplicatesAndEmptyNames() {
        let plan = TidyTabs.plan([.init(name: "Planets", tabs: [6, 0, 3, 99, -1]),
                                  .init(name: "Bread", tabs: [1, 4, 7, 0]),
                                  .init(name: "Email", tabs: [8]),
                                  .init(name: "  ", tabs: [2, 5])],
                                 tabCount: 9, existingGroups: [])
        #expect(plan.newGroups == [.init(name: "Planets", tabs: [0, 3, 6]), .init(name: "Bread", tabs: [1, 4, 7]), .init(name: "Email", tabs: [8])])
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
