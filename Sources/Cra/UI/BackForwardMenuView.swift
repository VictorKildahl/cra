import AppKit

/// One row of Back or Forward's history menu (#416): the page's favicon and its title.
struct BackForwardMenuItem {
    let title: String
    let icon: NSImage?
    /// A one-colour glyph (GitHub's) drawn white, as on the sidebar's dark fills. No icon: Arc's
    /// grey square.
    let flip: Bool
}

/// Arc's BackForwardList menu: its ArcMenu hung under Back or Forward, tail up, the nearest page
/// first. Geometry from CraCore's BackForwardMenu.Layout, colours from the space (ArcMenuTones).
@MainActor
final class BackForwardMenuView: NSView, ArcMenuContent {
    private typealias L = BackForwardMenu.Layout
    private let items: [BackForwardMenuItem]
    var rowCount: Int { items.count }
    private let colors: SidebarCreationMenuColors
    private let onPick: (Int?) -> Void
    /// Nothing is picked until the pointer or an arrow key picks a row.
    private(set) var selected: Int? { didSet { if selected != oldValue { needsDisplay = true } } }
    private var pressed: Int?
    var arrowX: CGFloat = L.margin + L.width / 2 { didSet { needsDisplay = true } }

    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    init(items: [BackForwardMenuItem], colors: SidebarCreationMenuColors = .init(), onPick: @escaping (Int?) -> Void) {
        self.items = items
        self.colors = colors
        self.onPick = onPick
        super.init(frame: NSRect(origin: .zero, size: L.size(rows: items.count)))
        wantsLayer = true
        // Arc draws a soft shadow inside its window's 6 pt margin, with no rim round the menu
        // (the window's own shadow adds one on macOS 26).
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        setAccessibilityRole(.menu)
        for (index, item) in items.enumerated() {
            let rect = L.rowRect(index)
            let row = NSButton(frame: rect)
            row.cell = BackForwardMenuCell(textCell: item.title)
            row.isBordered = false
            row.setAccessibilityRole(.menuItem)
            row.setAccessibilityLabel(item.title)
            row.target = self
            row.action = #selector(choose(_:))
            row.tag = index
            let favicon = L.faviconRect(index)
            let icon = NSImageView(frame: NSRect(x: favicon.minX - rect.minX, y: favicon.minY - rect.minY,
                                                 width: favicon.width, height: favicon.height))
            icon.wantsLayer = true
            icon.layer?.cornerCurve = .continuous
            if let image = item.icon {
                icon.imageScaling = .scaleProportionallyUpOrDown
                if item.flip {
                    let t = image.copy() as! NSImage
                    t.isTemplate = true
                    icon.image = t
                    icon.contentTintColor = NSColor.white.withAlphaComponent(0.92)
                } else {
                    icon.image = image
                }
                icon.layer?.cornerRadius = L.faviconSize * 0.22
                icon.layer?.masksToBounds = true
            } else {
                // Arc's stand-in for a page with no favicon: a 14 pt rounded square, white at 35 %.
                let inset = (L.faviconSize - L.placeholderSize) / 2
                let square = NSView(frame: NSRect(x: inset, y: inset, width: L.placeholderSize, height: L.placeholderSize))
                square.wantsLayer = true
                square.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
                square.layer?.cornerRadius = 3
                square.layer?.cornerCurve = .continuous
                icon.addSubview(square)
            }
            row.addSubview(icon)
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    func animate(opening: Bool, delegate: CAAnimationDelegate? = nil) {
        ArcMenuMotion.animate(self, tip: CGPoint(x: arrowX, y: L.margin), opening: opening, delegate: delegate)
    }

    override func draw(_ dirtyRect: NSRect) {
        colors.fill.setFill()
        NSBezierPath(roundedRect: L.fillRect(rows: items.count), xRadius: L.cornerRadius, yRadius: L.cornerRadius).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: arrowX - L.tailHalfWidth, y: L.margin + L.tailHeight))
        tail.line(to: NSPoint(x: arrowX, y: L.margin))
        tail.line(to: NSPoint(x: arrowX + L.tailHalfWidth, y: L.margin + L.tailHeight))
        tail.close()
        tail.fill()
        if let selected {
            colors.hover.setFill()
            NSBezierPath(roundedRect: L.rowRect(selected), xRadius: L.rowCornerRadius, yRadius: L.rowCornerRadius).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: NSColor.white]
        for (index, item) in items.enumerated() {
            let rect = L.rowRect(index)
            let text = Self.fitted(item.title) as NSString
            let height = text.size(withAttributes: attributes).height
            text.draw(at: NSPoint(x: L.margin + L.titleX, y: rect.midY - height / 2), withAttributes: attributes)
        }
    }

    /// The title cut to fit, as Arc cuts it: the longest start that fits with "…" after it.
    /// (AppKit's own tail truncation lets a cut title run up to 4 pt past its box, so it keeps a
    /// letter more or less than Arc does.)
    static func fitted(_ title: String, width: CGFloat = BackForwardMenu.Layout.titleWidth) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont]
        func fits(_ s: String) -> Bool { (s as NSString).size(withAttributes: attributes).width <= width }
        let line = title.replacingOccurrences(of: "\n", with: " ")
        if fits(line) { return line }
        let characters = Array(line)
        var low = 0, high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(String(characters[..<mid]).trimmingCharacters(in: .whitespaces) + "…") { low = mid } else { high = mid - 1 }
        }
        return String(characters[..<low]).trimmingCharacters(in: .whitespaces) + "…"
    }

    @objc private func choose(_ sender: NSButton) { onPick(sender.tag) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func index(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return items.indices.first { L.rowRect($0).contains(point) }
    }

    override func mouseMoved(with event: NSEvent) { selected = index(at: event) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { selected = nil }
    override func mouseDown(with event: NSEvent) { pressed = index(at: event) }
    override func mouseUp(with event: NSEvent) {
        if let pressed, index(at: event) == pressed { onPick(pressed) }
        pressed = nil
    }
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: onPick(nil)
        case 36, 76:
            if let selected { onPick(selected) }
        case 125, 126:
            guard !items.isEmpty else { return true }
            let step = event.keyCode == 125 ? 1 : -1
            let current = selected ?? (step == 1 ? -1 : items.count)
            selected = (current + step + items.count) % items.count
        default: return false
        }
        return true
    }
}

private final class BackForwardMenuCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
}
