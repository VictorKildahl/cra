import CraCore
import Foundation
import Testing

/// GitHub #154: Arc's one favorites list per profile, as a setting.
struct FavoritesSharingTests {
    typealias S = FavoritesSharing.SpaceFavorites
    typealias E = FavoritesSharing.Entry

    static func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    @Test func eachProfileTakesItsFirstSpacesList() {
        let sp = Self.ids(4), c = Self.ids(4), f = Self.ids(5), work = UUID()
        let plan = FavoritesSharing.share([
            S(spaceID: sp[0], profileID: nil, containerID: c[0], items: [E(id: f[0], key: "tab https://mail.example")]),
            S(spaceID: sp[1], profileID: work, containerID: c[1], items: [E(id: f[1], key: "tab https://jira.example")]),
            S(spaceID: sp[2], profileID: nil, containerID: c[2], items: [E(id: f[2], key: "tab https://music.example"),
                                                                     E(id: f[3], key: "tab https://mail.example")]),
            S(spaceID: sp[3], profileID: work, containerID: c[3], items: [E(id: f[4], key: nil)]),
        ])
        #expect(plan.containers == [sp[0]: c[0], sp[1]: c[1], sp[2]: c[0], sp[3]: c[1]])
        #expect(plan.owners == [c[0]: sp[0], c[1]: sp[1]])
        #expect(plan.moves == [.init(item: f[2], container: c[0]), .init(item: f[4], container: c[1])])
        #expect(plan.duplicates == [f[3]: f[0]], "the same page once: the first space's tile stays")
        #expect(plan.dropped == [c[2], c[3]])
        #expect(plan.created.isEmpty)
    }

    /// Turning it off copies the list into the other spaces; turning it on again finds every copy
    /// the same as the original, so the list comes back as it was, not doubled.
    @Test func offAndOnAgainChangesNothing() {
        let sp = Self.ids(3), c = Self.ids(3), f = Self.ids(4)
        let shared = [E(id: f[0], key: "tab https://a.example"), E(id: f[1], key: "split https://b.example https://c.example")]
        let off = FavoritesSharing.unshare(sp.map { S(spaceID: $0, profileID: nil, containerID: c[0], items: shared) })
        #expect(off == [sp[1]: c[0], sp[2]: c[0]])
        let copy = [E(id: f[2], key: shared[0].key), E(id: f[3], key: shared[1].key)]
        let on = FavoritesSharing.share([S(spaceID: sp[0], profileID: nil, containerID: c[0], items: shared),
                                         S(spaceID: sp[1], profileID: nil, containerID: c[1], items: copy),
                                         S(spaceID: sp[2], profileID: nil, containerID: c[2], items: [])])
        #expect(on.moves.isEmpty)
        #expect(on.duplicates == [f[2]: f[0], f[3]: f[1]])
        #expect(on.dropped == [c[1], c[2]])
    }

    @Test func alreadySharedListsStayPut() {
        let sp = Self.ids(3), c = UUID(), f = UUID()
        let items = [E(id: f, key: "tab https://a.example")]
        let plan = FavoritesSharing.share(sp.map { S(spaceID: $0, profileID: nil, containerID: c, items: items) })
        #expect(plan.containers == [sp[0]: c, sp[1]: c, sp[2]: c])
        #expect(plan.moves.isEmpty && plan.duplicates.isEmpty && plan.dropped.isEmpty && plan.created.isEmpty)
        #expect(FavoritesSharing.unshare([S(spaceID: sp[0], profileID: nil, containerID: c, items: items)]).isEmpty)
    }

    /// Sharing in the middle of a space's profile change (a hand-edited file): the space keeps
    /// its favorites where they are, and its new profile starts a list of its own.
    @Test func aListAnotherProfileShowsIsNotTaken() {
        let sp = Self.ids(2), c = UUID(), new = UUID(), work = UUID()
        let plan = FavoritesSharing.share([S(spaceID: sp[0], profileID: nil, containerID: c, items: []),
                                           S(spaceID: sp[1], profileID: work, containerID: c, items: [])], newID: { new })
        #expect(plan.containers == [sp[0]: c, sp[1]: new])
        #expect(plan.created == [new] && plan.owners == [c: sp[0], new: sp[1]])
        #expect(plan.dropped.isEmpty)
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
}
