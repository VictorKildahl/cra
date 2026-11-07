import AppKit

/// The menu bar item of Settings ▸ Advanced ▸ "Keep Cra in the menu bar" (GitHub #231). Arc has
/// none, so it is a plain macOS status item: Cra's C mark as a template image, and a menu that
/// AppDelegate builds each time it opens (the shortcuts follow Settings ▸ Shortcuts).
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let build: (NSMenu) -> Void

    init(build: @escaping (NSMenu) -> Void) {
        self.build = build
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.icon
        item.button?.setAccessibilityLabel("Cra")
        item.button?.toolTip = "Cra"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        build(menu)
    }

    /// resources/brand/cra-mark-mono: one arc of radius 18 and width 19 on a 64-point square,
    /// open to the right between ±52°, with round ends. 16 pt, like the system's own items.
    static let icon: NSImage = {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let scale = rect.height / 55  // the ink is 55 tall and 48 wide, its middle 3.5 left of the arc's centre
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: rect.midX + 3.5 * scale, y: rect.midY), radius: 18 * scale,
                           startAngle: 52, endAngle: 308)
            path.lineWidth = 19 * scale
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
