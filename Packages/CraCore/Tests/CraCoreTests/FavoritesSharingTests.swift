import CraCore
import Foundation
import Testing

/// GitHub #154: Arc's one favorites list per profile, as a setting.
struct FavoritesSharingTests {
    typealias S = FavoritesSharing.SpaceFavorites
    typealias E = FavoritesSharing.Entry
    typealias L = FavoritesSharing.ProfileList

    static func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    @Test func eachProfileGetsOneListOfItsSpacesFavorites() {
        let sp = Self.ids(4), c = Self.ids(4), f = Self.ids(5), made = Self.ids(2), work = UUID()
        var next = made.makeIterator()
        let plan = FavoritesSharing.share([
            S(spaceID: sp[0], profileID: nil, containerID: c[0], items: [E(id: f[0], key: "tab https://mail.example")]),
            S(spaceID: sp[1], profileID: work, containerID: c[1], items: [E(id: f[1], key: "tab https://jira.example")]),
            S(spaceID: sp[2], profileID: nil, containerID: c[2], items: [E(id: f[2], key: "tab https://music.example"),
                                                                     E(id: f[3], key: "tab https://mail.example")]),
            S(spaceID: sp[3], profileID: work, containerID: c[3], items: [E(id: f[4], key: nil)]),
        ], lists: [], newID: { next.next()! })
        #expect(plan.created == made)
        #expect(plan.lists == [ProfileFavorites(profileID: nil, containerID: made[0]), ProfileFavorites(profileID: work, containerID: made[1])])
        #expect(plan.containers == [sp[0]: made[0], sp[1]: made[1], sp[2]: made[0], sp[3]: made[1]])
        #expect(plan.moves == [.init(item: f[0], container: made[0]), .init(item: f[1], container: made[1]),
                               .init(item: f[2], container: made[0]), .init(item: f[4], container: made[1])])
        #expect(plan.duplicates == [f[3]: f[0]], "the same page once: the first space's tile stays")
        #expect(plan.dropped == c)
    }

    /// Arc keeps a profile's list while no space uses it; turning sharing on again starts from it.
    @Test func aProfilesListIsReused() {
        let sp = UUID(), c = UUID(), list = UUID(), f = Self.ids(3)
        let plan = FavoritesSharing.share(
            [S(spaceID: sp, profileID: nil, containerID: c, items: [E(id: f[1], key: "tab https://a.example"), E(id: f[2], key: "tab https://b.example")])],
            lists: [L(ProfileFavorites(profileID: nil, containerID: list), items: [E(id: f[0], key: "tab https://a.example")])],
            newID: { Issue.record("no new list"); return UUID() })
        #expect(plan.created.isEmpty && plan.containers == [sp: list])
        #expect(plan.moves == [.init(item: f[2], container: list)] && plan.duplicates == [f[1]: f[0]])
    }

    @Test func twoOfAPageInOneSpaceBothStay() {
        let sp = UUID(), c = UUID(), f = Self.ids(2)
        let plan = FavoritesSharing.share([S(spaceID: sp, profileID: nil, containerID: c,
                                             items: [E(id: f[0], key: "tab https://a.example"), E(id: f[1], key: "tab https://a.example")])], lists: [])
        #expect(plan.moves.map(\.item) == f && plan.duplicates.isEmpty)
    }

    /// Off gives each space its own list again; on folds the copies back, so the list comes back
    /// as it was, not doubled.
    @Test func offAndOnAgainChangesNothing() {
        let sp = Self.ids(3), list = UUID(), c = Self.ids(2), f = Self.ids(4)
        let shared = [E(id: f[0], key: "tab https://a.example"), E(id: f[1], key: "split https://b.example https://c.example")]
        let lists = [ProfileFavorites(profileID: nil, containerID: list)]
        let off = FavoritesSharing.unshare(sp.map { S(spaceID: $0, profileID: nil, containerID: list, items: shared) }, lists: lists)
        #expect(off == [.init(spaceID: sp[0], from: list, takes: true), .init(spaceID: sp[1], from: list, takes: false),
                        .init(spaceID: sp[2], from: list, takes: false)])
        let copy = [E(id: f[2], key: shared[0].key), E(id: f[3], key: shared[1].key)]
        let on = FavoritesSharing.share([S(spaceID: sp[0], profileID: nil, containerID: c[0], items: shared),
                                         S(spaceID: sp[1], profileID: nil, containerID: c[1], items: copy)],
                                        lists: [L(lists[0], items: [])], newID: { Issue.record("no new list"); return UUID() })
        #expect(on.moves.map(\.item) == [f[0], f[1]])
        #expect(on.duplicates == [f[2]: f[0], f[3]: f[1]])
    }

    @Test func sharedListsStayPut() {
        let sp = Self.ids(2), list = UUID(), work = UUID(), f = UUID()
        let lists = [L(ProfileFavorites(profileID: work, containerID: list), items: [E(id: f, key: "tab https://a.example")])]
        let plan = FavoritesSharing.share(sp.map { S(spaceID: $0, profileID: work, containerID: list, items: lists[0].items) }, lists: lists)
        #expect(plan.containers == [sp[0]: list, sp[1]: list] && plan.lists == [lists[0].list])
        #expect(plan.moves.isEmpty && plan.duplicates.isEmpty && plan.dropped.isEmpty && plan.created.isEmpty)
        #expect(FavoritesSharing.unshare([S(spaceID: sp[0], profileID: nil, containerID: UUID(), items: [])], lists: [lists[0].list]).isEmpty,
                "a space with its own list keeps it")
    }

    @Test func keys() {
        let tab = SidebarItem.tab("https://mail.example/inbox", parent: nil)
        #expect(FavoritesSharing.key(of: tab, children: []) == "tab https://mail.example/inbox")
        #expect(FavoritesSharing.key(of: SidebarItem.tab("", parent: nil), children: []) == nil, "an empty pane matches nothing")
        let split = SidebarItem.split(parent: nil)
        let panes = [SidebarItem.tab("https://a.example", parent: split.id), SidebarItem.tab("https://b.example", parent: split.id)]
        #expect(FavoritesSharing.key(of: split, children: panes) == "split https://a.example https://b.example")
        #expect(FavoritesSharing.key(of: split, children: panes.reversed()) != FavoritesSharing.key(of: split, children: panes))
        #expect(FavoritesSharing.key(of: split, children: [panes[0], SidebarItem.tab("", parent: split.id)]) == nil)
        #expect(FavoritesSharing.key(of: SidebarItem.folder("F", parent: nil), children: []) == nil)
    }

    @Test func settingIsOffUntilTurnedOn() throws {
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!empty.sharedFavorites)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"sharedFavorites": true}"#.utf8))
        #expect(on.sharedFavorites)
    }

    @Test func listsRoundTrip() throws {
        var doc = SidebarDocument.fresh()
        doc.profileFavorites = [ProfileFavorites(profileID: nil, containerID: UUID()), ProfileFavorites(profileID: UUID(), containerID: UUID())]
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(SidebarDocument.self, from: data).profileFavorites == doc.profileFavorites)
        #expect(SidebarDocument.fresh().profileFavorites == nil, "files without shared favorites don't change")
    }
}
