import CraCore
import Foundation
import Testing

/// Share Folder… (GitHub #357): the folder travels in the link, after the #, so crabrowser.app
/// stores nothing. These pin what goes in and the version-1 format links already sent rely on.
struct FolderShareLinkTests {
    /// A sidebar: Trip ▸ Flights, a split (Hotel, Map), Ideas ▸ Food, Empty ▸ cra://settings.
    private func sidebar() -> (SidebarItem, [UUID: [SidebarItem]]) {
        let trip = SidebarItem.folder("Trip", parent: nil)
        let flights = SidebarItem.tab("https://flights.example/search?to=CPH", title: "Flights to Copenhagen", parent: trip.id)
        let split = SidebarItem.split(parent: trip.id)
        let hotel = SidebarItem.tab("https://hotel.example/", title: "Hotel", parent: split.id)
        let map = SidebarItem.tab("https://maps.example/@55.67,12.56", title: "", parent: split.id)
        let ideas = SidebarItem.folder("Ideas", parent: trip.id)
        let food = SidebarItem.tab("https://food.example/cph", title: "Food", parent: ideas.id)
        let empty = SidebarItem.folder("Empty", parent: trip.id)
        let settings = SidebarItem.tab("cra://settings", title: "Settings", parent: empty.id)
        return (trip, [trip.id: [flights, split, ideas, empty], split.id: [hotel, map], ideas.id: [food], empty.id: [settings]])
    }

    private var expected: FolderShareLink.Folder {
        FolderShareLink.Folder(title: "Trip", items: [
            .link(title: "Flights to Copenhagen", url: "https://flights.example/search?to=CPH"),
            .link(title: "Hotel", url: "https://hotel.example/"),
            .link(title: "maps.example", url: "https://maps.example/@55.67,12.56"),
            .folder(title: "Ideas", items: [.link(title: "Food", url: "https://food.example/cph")]),
        ])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/357"))
    func sharesTheFolderAsTheSidebarShowsIt() throws {
        let (trip, tree) = sidebar()
        let folder = FolderShareLink.folder(trip) { tree[$0] ?? [] }
        #expect(folder == expected)
        let link = try #require(FolderShareLink.url(for: folder))
        #expect(link.hasPrefix("https://crabrowser.app/folder#"))
        // Nothing readable before the #: the server sees only /folder.
        #expect(!link.contains("?"))
        #expect(FolderShareLink.folder(from: link) == folder)
    }

    /// A link made by this version. If this fails, links people already sent stop opening.
    static let versionOneLink = "https://crabrowser.app/folder#XY7NCoMwEIRfRfYcDBZiIVBaEMTeeuit9BB0awQ1wWxLQfLutQpBcpyfb5gZOpCPGQgklH3XanIJmaQwFketWhyBwXvJNJF1kvPX1knxqwbbI3eoplqfyZyKWwWebUuVIewjUv-9wIXqoGxYi4h9xC9CpPmRZYdU5Cu8-21ME99crIDWVoN_srV7bVC5oO5TZxfyAzLzPw"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/357"))
    func versionOneStillOpens() {
        #expect(FolderShareLink.folder(from: Self.versionOneLink) == expected)
    }

    @Test func pinnedTabSharesItsPinnedPageUnderItsName() throws {
        let folder = SidebarItem.folder("Work", parent: nil)
        var moved = SidebarItem.tab("https://docs.example/home", title: "Docs Home", parent: folder.id)
        moved.data = .tab({ var t = moved.tab!; t.noteTitle("Docs Home", pinned: true); t.url = "https://docs.example/page/42"; t.savedTitle = "Page 42"; return t }())
        var renamed = SidebarItem.tab("https://mail.example/", title: "Inbox (3)", parent: folder.id)
        renamed.title = "Mail"
        let shared = FolderShareLink.folder(folder) { $0 == folder.id ? [moved, renamed] : [] }
        #expect(shared.items == [.link(title: "Docs Home", url: "https://docs.example/home"),
                                 .link(title: "Mail", url: "https://mail.example/")])
    }

    @Test func nothingToShareGivesNoLink() {
        let folder = SidebarItem.folder("Local", parent: nil)
        let file = SidebarItem.tab("file:///Users/me/notes.txt", title: "Notes", parent: folder.id)
        let blank = SidebarItem.tab("about:blank", parent: folder.id)
        #expect(FolderShareLink.url(for: FolderShareLink.folder(folder) { _ in [file, blank] }) == nil)
        #expect(FolderShareLink.url(for: .init(title: "None", items: [])) == nil)
    }

    /// Anyone can write a link by hand: one that isn't a web page never comes out of it.
    @Test func craftedLinksKeepOnlyWebPages() throws {
        let json = #"{"v":1,"t":"x","i":[{"t":"a","u":"javascript:alert(1)"},{"t":"b","u":"data:text/html,hi"},{"t":"c","u":"https://ok.example/"}]}"#
        let link = FolderShareLink.prefix + base64URL(try deflate(Data(json.utf8)))
        #expect(FolderShareLink.folder(from: link) == .init(title: "x", items: [.link(title: "c", url: "https://ok.example/")]))
        #expect(FolderShareLink.folder(from: "https://crabrowser.app/folder#not-a-folder") == nil)
        let later = #"{"v":2,"t":"x","i":[{"t":"c","u":"https://ok.example/"}]}"#
        #expect(FolderShareLink.folder(from: FolderShareLink.prefix + base64URL(try deflate(Data(later.utf8)))) == nil)
    }

    @Test func longTitlesAreCut() throws {
        let long = String(repeating: "a", count: 500)
        let folder = FolderShareLink.Folder(title: long, items: [.link(title: long, url: "https://a.example/")])
        let link = try #require(FolderShareLink.url(for: folder))
        let back = try #require(FolderShareLink.folder(from: link))
        #expect(back.title.count == FolderShareLink.titleLimit)
        #expect(back.title.hasSuffix("…"))
    }

    private func deflate(_ data: Data) throws -> Data { try (data as NSData).compressed(using: .zlib) as Data }
    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
