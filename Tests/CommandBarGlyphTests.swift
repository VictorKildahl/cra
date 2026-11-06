import Foundation

/// The command bar's leading glyph against what Arc 1.171 showed (GitHub #50).
@main
enum CommandBarGlyphTests {
    private static var checks = 0

    static func main() {
        leadingGlyph()
        print("CommandBarGlyph: \(checks) checks passed")
    }

    // promise: #50
    /// The glyph is the highlighted row's icon; with nothing typed ⌘L shows the page's favicon and
    /// ⌘T a magnifier (#50).
    private static func leadingGlyph() {
        let cached: Set<String> = ["github.com", "youtube.com", "x.com"]
        func glyph(editingURL: Bool = false, untouched: Bool = false, site: Bool = false, page: String? = nil,
                   row: (String?, String?)?) -> CommandBarGlyph {
            CommandBarGlyph.resolve(editingURL: editingURL, untouched: untouched, scoped: site, pageFaviconKey: page,
                                    row: row.map { (faviconKey: $0.0, symbol: $0.1) }, hasFavicon: cached.contains)
        }
        let recentTab = ("github.com", nil as String?)

        // Nothing typed: ⌘L shows the page's favicon (a globe without one), ⌘T a magnifier.
        expect(glyph(editingURL: true, untouched: true, page: "github.com", row: recentTab) == .favicon("github.com"), "⌘L, page favicon")
        expect(glyph(editingURL: true, untouched: true, page: "example.com", row: recentTab) == .symbol("globe"), "⌘L, page without favicon")
        expect(glyph(untouched: true, row: recentTab) == .symbol("magnifyingglass"), "⌘T, empty")

        // Typed: the highlighted row's icon, in both modes.
        for editing in [false, true] {
            expect(glyph(editingURL: editing, row: (nil, "magnifyingglass")) == .symbol("magnifyingglass"), "hello world → search row")
            expect(glyph(editingURL: editing, row: ("example.org", "globe")) == .symbol("globe"), "example.org → URL row, no favicon")
            expect(glyph(editingURL: editing, row: ("youtube.com", "globe")) == .favicon("youtube.com"), "youtube.com → URL row's favicon")
            expect(glyph(editingURL: editing, row: ("x.com", nil)) == .favicon("x.com"), "x.com → completing tab")
            expect(glyph(editingURL: editing, row: ("jira.example", nil)) == .symbol("globe"), "tab row without a cached favicon")
        }
        expect(glyph(site: true, row: ("youtube.com", nil)) == .symbol("magnifyingglass"), "site search or the tabs scope")
        expect(glyph(row: nil) == .symbol("magnifyingglass"), "no rows")
    }

    private static func expect(_ ok: Bool, _ what: String) {
        checks += 1
        if !ok {
            print("FAIL: \(what)")
            exit(1)
        }
    }
}
