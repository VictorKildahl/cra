import AppKit

/// A space's icon at menu size, as Arc shows it before Tabs ▸ "Open in <space>": the emoji, or the
/// SF Symbol picked in its icon picker; nil for a space with neither. A picture the user chose comes first, in full colour.
@MainActor
enum SpaceMenuIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for space: Space) -> NSImage? {
        if let data = space.iconImage, !data.isEmpty { return SpaceIconImage.image(data, points: 16) }
        return image(emoji: space.emoji, symbol: space.symbol)
    }

    /// An emoji drawn in a 16 pt square, or a template SF Symbol (tinted by its view); nil for neither.
    /// A split's icon (#600) uses it too, `size` being the emoji's point size.
    static func image(emoji: String, symbol: String?, size: CGFloat = 13) -> NSImage? {
        if let symbol, !symbol.isEmpty {
            let image = SidebarSymbols.image(symbol, size: size)
            image?.isTemplate = true
            return image
        }
        guard !emoji.isEmpty else { return nil }
        let key = "\(emoji)@\(size)"
        if let hit = cache[key] { return hit }
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let side = ceil(size * 16 / 13)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let s = text.size()
            text.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
            return true
        }
        cache[key] = image
        return image
    }
}
