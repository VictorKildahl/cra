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

    /// A file dragged out of the downloads tray (or the Finder) carries its file URL
    /// (`public.file-url`); let go on the list, one Chromium shows in a tab (an image, a PDF, a
    /// page, text, audio or video) opens as a tab there, as in Arc. Others would only download again.
    static let fileCases: [(String, [Item], SidebarLinkDrop.Tab?)] = [
        ("downloaded pdf", [Item(file: "file:///Users/me/Downloads/Report.pdf")],
         .init(url: "file:///Users/me/Downloads/Report.pdf", title: "")),
        ("upper-case extension", [Item(file: "file:///tmp/SCAN.PDF")], .init(url: "file:///tmp/SCAN.PDF", title: "")),
        ("png", [Item(file: "file:///tmp/shot.png")], .init(url: "file:///tmp/shot.png", title: "")),
        ("jpeg", [Item(file: "file:///tmp/a%20photo.JPEG")], .init(url: "file:///tmp/a%20photo.JPEG", title: "")),
        ("gif", [Item(file: "file:///tmp/a.gif")], .init(url: "file:///tmp/a.gif", title: "")),
        ("webp", [Item(file: "file:///tmp/a.webp")], .init(url: "file:///tmp/a.webp", title: "")),
        ("svg", [Item(file: "file:///tmp/a.svg")], .init(url: "file:///tmp/a.svg", title: "")),
        ("html file", [Item(file: "file:///Users/me/a.html")], .init(url: "file:///Users/me/a.html", title: "")),
        ("text", [Item(file: "file:///tmp/notes.txt")], .init(url: "file:///tmp/notes.txt", title: "")),
        ("json", [Item(file: "file:///tmp/data.json")], .init(url: "file:///tmp/data.json", title: "")),
        ("video", [Item(file: "file:///tmp/clip.mp4")], .init(url: "file:///tmp/clip.mp4", title: "")),
        ("audio", [Item(file: "file:///tmp/song.mp3")], .init(url: "file:///tmp/song.mp3", title: "")),
        ("zip", [Item(file: "file:///Users/me/Downloads/a.zip")], nil),
        ("disk image", [Item(file: "file:///Users/me/Downloads/App.dmg")], nil),
        ("no extension", [Item(file: "file:///etc/hosts")], nil),
        ("folder named .png", [Item(file: "file:///tmp/x.png/")], nil),
        ("not a file url", [Item(file: "/tmp/a.pdf")], nil),
        // Only a file's own drag: a page's link to a file stays refused (#419, above).
        ("pdf as a link", [Item(url: "file:///tmp/a.pdf")], nil),
        ("web link first", [Item(url: "https://a.org"), Item(file: "file:///tmp/a.pdf")], .init(url: "https://a.org", title: "")),
    ]

    @Test(arguments: fileCases.indices)
    func aDroppedFileChromiumShowsOpensAsATab(_ i: Int) {
        let (name, items, tab) = Self.fileCases[i]
        #expect(SidebarLinkDrop.tab(from: items) == tab, "\(name)")
    }
}
