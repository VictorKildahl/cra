import AppKit

/// The popover under the narrow sidebar header's ••• (Arc 1.17x, issue #287): a dark panel in
/// the space's tones with an arrow up to the button, one 40 pt row per command (icon, title,
/// shortcut), the hovered row filled. Geometry and tones are in CraCore's `SidebarMoreMenu`.
/// It opens with the first enabled row highlighted; the highlight then follows the pointer over
/// enabled rows and clears anywhere else. A pick or a click anywhere else closes it; keys don't
/// (Arc 1.17x: Escape and the arrows left it open, live 9 Nov 2026).
@MainActor
final class SidebarMorePanel: NSPanel {
    struct Item {
        let symbol: String
        let title: String
        let keys: [String]
        let enabled: Bool
        let run: () -> Void
    }

    /// Called once the panel has closed, however it closed.
    var onClose: (() -> Void)?
    /// The button that opened it (screen rect): a click there closes the panel and goes no further,
    /// so the button doesn't open it again.
    private var anchor = NSRect.zero
    private var monitors: [Any] = []
    private var closing = false

    init(items: [Item], ink: RGB) {
        let size = NSSize(width: SidebarMoreMenu.width,
                          height: SidebarMoreMenu.height(rows: items.count) + SidebarMoreMenu.arrowHeight)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        let view = SidebarMoreMenuView(frame: NSRect(origin: .zero, size: size), items: items, ink: ink)
        view.onPick = { [weak self] item in
            self?.dismiss()
            item.run()
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Opens under `button` (a rect on screen), centred on it, the arrow's tip 10 pt below it.
    func show(under button: NSRect, in parent: NSWindow) {
        anchor = button
        let tipY = button.minY - SidebarMoreMenu.arrowGap
        setFrameOrigin(NSPoint(x: (button.midX - frame.width / 2).rounded(), y: tipY - frame.height))
        parent.addChildWindow(self, ordered: .above)
        orderFront(nil)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            guard let self else { return e }
            if e.window === self { return e }
            let onAnchor = self.anchor.contains(NSEvent.mouseLocation)
            self.dismiss()
            guard onAnchor else { return e }
            // The button acts on mouse-up: eat that one too, or it opens the panel again.
            var up: Any?
            up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { _ in
                if let m = up { NSEvent.removeMonitor(m) }
                up = nil
                return nil
            }
            return nil
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        } as Any)
        NotificationCenter.default.addObserver(self, selector: #selector(parentChanged), name: NSWindow.didResignKeyNotification, object: parent)
        NotificationCenter.default.addObserver(self, selector: #selector(parentChanged), name: NSWindow.willCloseNotification, object: parent)
    }

    @objc private func parentChanged() { dismiss() }

    func dismiss() {
        guard !closing else { return }
        closing = true
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        orderOut(nil)
        onClose?()
    }
}

/// Draws the panel: the arrow, the rounded body, the rows; tracks the hovered row.
private final class SidebarMoreMenuView: NSView {
    var onPick: ((SidebarMorePanel.Item) -> Void)?
    private let items: [SidebarMorePanel.Item]
    private let fill: NSColor
    private let highlight: NSColor
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let keyFont = NSFont.systemFont(ofSize: 13)
    /// Measured on Arc's popover: a disabled row's icon and text, an enabled row's shortcut.
    private static let disabled = NSColor(srgbRed: 121 / 255, green: 120 / 255, blue: 129 / 255, alpha: 1)
    private static let shortcut = NSColor.white.withAlphaComponent(0.3)

    init(frame: NSRect, items: [SidebarMorePanel.Item], ink: RGB) {
        self.items = items
        fill = NSColor(SidebarMoreMenu.fill(shadedDark: ink))
        highlight = NSColor(SidebarMoreMenu.highlight(shadedDark: ink))
        super.init(frame: frame)
        hovered = items.firstIndex { $0.enabled }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rowRect(_ i: Int) -> NSRect {
        let m = SidebarMoreMenu.self
        return NSRect(x: m.inset, y: m.arrowHeight + m.inset + Double(i) * m.rowHeight,
                      width: bounds.width - 2 * m.inset, height: m.rowHeight)
    }

    /// The enabled row under `p`; nil over a disabled row, the padding or outside.
    private func row(at p: NSPoint) -> Int? {
        items.indices.first { rowRect($0).contains(p) && items[$0].enabled }
    }

    override func mouseMoved(with event: NSEvent) { hovered = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard let i = row(at: convert(event.locationInWindow, from: nil)) else { return }
        onPick?(items[i])
    }

    override func draw(_ dirtyRect: NSRect) {
        let m = SidebarMoreMenu.self
        let w = bounds.width, mid = w / 2
        let body = NSBezierPath(roundedRect: NSRect(x: 0, y: m.arrowHeight, width: w, height: bounds.height - m.arrowHeight),
                                xRadius: m.cornerRadius, yRadius: m.cornerRadius)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: mid - m.arrowWidth / 2, y: m.arrowHeight + 0.5))
        arrow.line(to: NSPoint(x: mid, y: 0))
        arrow.line(to: NSPoint(x: mid + m.arrowWidth / 2, y: m.arrowHeight + 0.5))
        arrow.close()
        fill.setFill()
        body.fill()
        arrow.fill()

        for (i, item) in items.enumerated() {
            let r = rowRect(i)
            if hovered == i {
                highlight.setFill()
                NSBezierPath(roundedRect: r, xRadius: m.highlightRadius, yRadius: m.highlightRadius).fill()
            }
            let ink = item.enabled ? NSColor.white : Self.disabled
            if let img = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium).applying(.init(paletteColors: [ink]))) {
                let s = img.size
                img.draw(in: NSRect(x: (m.iconCentre - s.width / 2).rounded(), y: (r.midY - s.height / 2).rounded(),
                                    width: s.width, height: s.height))
            }
            let title = NSAttributedString(string: item.title, attributes: [.font: Self.titleFont, .foregroundColor: ink])
            let ts = title.size()
            title.draw(at: NSPoint(x: m.titleX, y: (r.midY - ts.height / 2).rounded()))
            let keys = NSAttributedString(string: item.keys.joined(separator: " "),
                                          attributes: [.font: Self.keyFont, .foregroundColor: item.enabled ? Self.shortcut : Self.disabled])
            let ks = keys.size()
            keys.draw(at: NSPoint(x: (w - m.shortcutTrailing - ks.width).rounded(), y: (r.midY - ks.height / 2).rounded()))
        }
    }
}
