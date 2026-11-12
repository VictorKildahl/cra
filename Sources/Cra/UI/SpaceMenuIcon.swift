import AppKit

/// A space's icon at menu size, as Arc shows it before Tabs ▸ "Open in <space>": the emoji, or the
/// SF Symbol picked in its icon picker; nil for a space with neither.
@MainActor
enum SpaceMenuIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for space: Space) -> NSImage? {
        if let symbol = space.symbol, !symbol.isEmpty {
            let image = SidebarSymbols.image(symbol, size: 13)
            image?.isTemplate = true
            return image
        }
        guard !space.emoji.isEmpty else { return nil }
        if let hit = cache[space.emoji] { return hit }
        let text = NSAttributedString(string: space.emoji, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = text.size()
            text.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
            return true
        }
        cache[space.emoji] = image
        return image
    }
}
