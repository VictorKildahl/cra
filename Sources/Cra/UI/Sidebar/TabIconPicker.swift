import AppKit
import SwiftUI

/// Change Icon… on a favorite or a tab's row (GitHub #640): Arc's Emoji | Icon picker, the one a space's
/// icon uses, with Cra's picture choice kept in it. What is picked becomes the tab's custom icon
/// (TabCustomIcon); Remove goes back to the site's icon.
@MainActor
enum TabIconPicker {
    /// The picker on screen, for scenarios.
    private(set) static weak var shown: NSPopover?

    static func show(for id: UUID, store: SidebarStore, favicons: FaviconCache, anchor: NSView, rect: NSRect) {
        guard store.item(id)?.tab != nil, let content = anchor.window?.contentView else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        let set: (SpaceIcon) -> Void = { [weak popover] icon in
            apply(icon, to: id, store: store, favicons: favicons)
            popover?.performClose(nil)
        }
        let picker = SpaceIconPicker(current: "", currentSymbol: nil,
                                     onPick: { set(.emoji($0)) }, onPickSymbol: { set(.symbol($0)) },
                                     onPickImage: { set(.image($0)) }, onRemove: { set(.none) })
        let host = NSHostingController(rootView: picker)
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: 272, height: 272)
        popover.contentViewController = host
        popover.contentSize = host.preferredContentSize
        // Arc hangs it under the tile or the icon, its arrow pointing up at it.
        popover.show(relativeTo: anchor.convert(rect, to: content), of: content, preferredEdge: content.isFlipped ? .maxY : .minY)
        shown = popover
    }

    /// A pick: the tab's custom icon, the one it had before thrown away.
    static func apply(_ icon: SpaceIcon, to id: UUID, store: SidebarStore, favicons: FaviconCache) {
        let old = store.item(id)?.tab?.customIconKey
        if case .none = icon {
            store.setCustomIcon(nil, for: id)
        } else {
            guard let key = favicons.importCustomIcon(icon) else { NSSound.beep(); return }
            store.setCustomIcon(key, for: id)
        }
        if let old { favicons.removeCustomIcon(old) }
    }
}

extension FaviconCache {
    /// A pick from Change Icon…'s picker (#640) as a custom icon: an emoji or a symbol drawn into a
    /// picture, or the picture itself. nil for Remove, and for what can't be drawn.
    func importCustomIcon(_ icon: SpaceIcon) -> String? {
        guard let prefix = TabCustomIcon.keyPrefix(for: icon) else { return nil }
        let image: NSImage?
        switch icon {
        case .emoji(let e):
            image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
                let font = NSFont.systemFont(ofSize: 100)
                let text = NSAttributedString(string: e, attributes: [.font: font])
                let size = text.size()
                text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
                return true
            }
        case .symbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 96, weight: .medium).applying(.init(paletteColors: [.black])))
        case .image(let data):
            image = NSImage(data: data)
        case .none:
            image = nil
        }
        return image.flatMap { importCustomIcon($0, prefix: prefix) }
    }
}
