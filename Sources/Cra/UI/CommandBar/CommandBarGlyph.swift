/// The glyph before the command bar's text (Arc 1.171, GitHub #50): the highlighted row's icon,
/// so it says what Return does: a site's favicon, a globe for a URL without one, a magnifier
/// for a search. Before anything is typed, ⌘L shows the page's favicon and ⌘T a magnifier.
enum CommandBarGlyph: Equatable {
    case favicon(String)
    case symbol(String)

    /// `untouched`: the field is empty, or still holds the URL ⌘L opened with, and no row is
    /// arrowed to. `row` is the highlighted row (the arrowed one, else the top one).
    static func resolve(editingURL: Bool, untouched: Bool, scoped: Bool, pageFaviconKey: String?,
                        row: (faviconKey: String?, symbol: String?)?, hasFavicon: (String) -> Bool) -> CommandBarGlyph {
        // Scoped to a site or to the open tabs (a pill before the field): a search.
        if scoped { return .symbol("magnifyingglass") }
        if untouched {
            guard editingURL else { return .symbol("magnifyingglass") }
            if let key = pageFaviconKey, hasFavicon(key) { return .favicon(key) }
            return .symbol("globe")
        }
        guard let row else { return .symbol("magnifyingglass") }
        if let key = row.faviconKey, hasFavicon(key) { return .favicon(key) }
        // A row without a favicon draws its symbol, a globe when it has none (CommandBarRowView).
        return .symbol(row.symbol ?? "globe")
    }
}
