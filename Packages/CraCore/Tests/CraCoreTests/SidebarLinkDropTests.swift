import CraCore
import Testing

/// A link dragged onto a space's tab list from a page or another app opens as a new tab (#419).
@Suite struct SidebarLinkDropTests {
    typealias Item = SidebarLinkDrop.Item

    /// What a pasteboard holds → the tab it opens, or nil when the list refuses it.
    static let cases: [(String, [Item], SidebarLinkDrop.Tab?)] = [
        // A link from a page (Chromium, Safari): the address and the link's text.
        ("page link", [Item(url: "https://example.com/a", name: "Example A", text: "https://example.com/a")],
         .init(url: "https://example.com/a", title: "Example A")),
        // Mail and Notes: the address alone.
        ("bare url", [Item(url: "https://example.com")], .init(url: "https://example.com", title: "")),
        // Text that is an address (a selection, the toolbar's field): no title, the page names it.
        ("text", [Item(text: "  http://example.org/x \n")], .init(url: "http://example.org/x", title: "")),
        // A link text over two lines reads as one.
        ("name over lines", [Item(url: "https://a.org", name: " Read\n  more ")], .init(url: "https://a.org", title: "Read more")),
        // A name that only repeats the address says nothing the page won't.
        ("name is the url", [Item(url: "https://a.org", name: "https://a.org")], .init(url: "https://a.org", title: "")),
        // Only web pages: a file from Finder, a script, a mail address.
        ("file", [Item(url: "file:///Users/me/a.html", text: "/Users/me/a.html")], nil),
        ("javascript", [Item(url: "javascript:alert(1)", name: "Click")], nil),
        ("mailto", [Item(url: "mailto:a@b.c")], nil),
        ("plain words", [Item(text: "hello world")], nil),
        ("nothing", [], nil),
        // The first item with a web address wins; one that has none is passed over.
        ("first link wins", [Item(url: "file:///tmp/x"), Item(url: "https://first.org"), Item(url: "https://second.org")],
         .init(url: "https://first.org", title: "")),
        // An item's URL over its text: the title belongs to the URL.
        ("url over text", [Item(url: "https://u.org", name: "U", text: "https://t.org")], .init(url: "https://u.org", title: "U")),
        // A name never comes with an address read from text.
        ("text keeps no name", [Item(url: "file:///x", name: "X", text: "https://t.org")], .init(url: "https://t.org", title: "")),
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/419"), arguments: cases.indices)
    func whichLinkBecomesTheTab(_ i: Int) {
        let (name, items, tab) = Self.cases[i]
        #expect(SidebarLinkDrop.tab(from: items) == tab, "\(name)")
    }
}
