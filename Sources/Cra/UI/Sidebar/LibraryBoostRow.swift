import AppKit

/// A boost on Library ▸ Boosts, as Arc 1.172.1 draws it (Victor's Arc, 8 Nov 2026, 2x stills):
/// the site's icon on a 43 pt light tile with a white rim, the boost's name (14 pt) over its site;
/// under the pointer a rounded card and a 36 × 22 pt switch 8 pt from the right (on: the theme's
/// dark shade with a light knob). A boost that's off keeps its row but its tile dims under a
/// diagonal stroke. Right-click: Rename, Delete.
final class BoostRowCell: NSView, NSTextFieldDelegate {
    private let card = FlippedView()
    private let tile = NSView()
    private let icon = NSImageView()
    private let strike = CAShapeLayer()
    private let strikeHalo = CAShapeLayer()
    private let title = NSTextField.sidebarLabel(size: 14)
    private let detail = NSTextField.sidebarLabel(size: 12.5)
    private let toggle = BoostSwitch()
    private var editor: NSTextField?
    private var boost: Boost?
    private var ink = NSColor.black
    private var hoverFill = NSColor.clear
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    private var downAt: NSPoint?
    var open: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        addSubview(card)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 12
        tile.layer?.cornerCurve = .continuous
        tile.layer?.borderWidth = 3
        tile.layer?.borderColor = NSColor.white.cgColor
        tile.layer?.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        tile.layer?.shadowColor = NSColor.black.cgColor
        tile.layer?.shadowOpacity = 0.12
        tile.layer?.shadowRadius = 2
        tile.layer?.shadowOffset = CGSize(width: 0, height: -1)
        icon.imageScaling = .scaleProportionallyUpOrDown
        tile.addSubview(icon)
        strikeHalo.lineCap = .round
        strikeHalo.lineWidth = 6.5
        strikeHalo.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        strike.lineCap = .round
        strike.lineWidth = 3.5
        card.addSubview(tile)
        card.addSubview(title)
        card.addSubview(detail)
        card.addSubview(toggle)
        tile.layer?.addSublayer(strikeHalo)
        tile.layer?.addSublayer(strike)
        toggle.onFlip = { [weak self] in self?.flip() }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ b: Boost, icon image: NSImage?, ink: NSColor, hoverFill: NSColor, tint: NSColor, knob: NSColor) {
        boost = b
        self.ink = ink
        self.hoverFill = hoverFill
        icon.image = image ?? NSImage(systemSymbolName: "paintbrush.pointed", accessibilityDescription: nil)
        icon.contentTintColor = image == nil ? NSColor.black.withAlphaComponent(0.5) : nil
        title.stringValue = b.name
        title.lineBreakMode = .byTruncatingTail
        title.textColor = ink.withAlphaComponent(0.85)
        detail.stringValue = b.host
        detail.textColor = ink.withAlphaComponent(0.5)
        toggle.set(on: b.enabled, tint: tint, knob: knob, ink: ink)
        setAccessibilityLabel("\(b.name), \(b.host)\(b.enabled ? "" : ", off")")
        refresh()
        needsLayout = true
    }

    private func refresh() {
        guard let b = boost else { return }
        card.layer?.backgroundColor = (hovering || editor != nil ? hoverFill : .clear).cgColor
        toggle.isHidden = !(hovering || editor != nil)
        tile.alphaValue = 1
        icon.alphaValue = b.enabled ? 1 : 0.5
        strike.isHidden = b.enabled
        strikeHalo.isHidden = b.enabled
        strike.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
    }

    private func flip() {
        guard var b = boost else { return }
        b.enabled.toggle()
        BoostStore.shared.update(b)
    }

    // MARK: Rename (Arc: in place)

    func beginRename() {
        guard let b = boost, editor == nil else { return }
        let f = NSTextField(string: b.name)
        f.font = title.font
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.textColor = title.textColor
        f.delegate = self
        f.frame = title.frame
        card.addSubview(f)
        editor = f
        title.isHidden = true
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = editor, var b = boost else { return }
        let name = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editor = nil
        f.removeFromSuperview()
        title.isHidden = false
        if !name.isEmpty, name != b.name {
            b.name = name
            BoostStore.shared.update(b)
        }
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)), let f = editor {
            f.stringValue = boost?.name ?? ""
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    // MARK: Layout and pointer

    override func layout() {
        super.layout()
        // The row's card lines up with the search field (7 pt in, 8 pt from the right).
        card.frame = NSRect(x: 7, y: 0, width: max(0, bounds.width - 15), height: bounds.height)
        let h = card.bounds.height, t: CGFloat = 43
        tile.frame = NSRect(x: 6, y: ((h - t) / 2).rounded(), width: t, height: t)
        icon.frame = NSRect(x: (t - 22) / 2, y: (t - 22) / 2, width: 22, height: 22)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 9, y: t - 9))
        line.addLine(to: CGPoint(x: t - 9, y: 9))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strike.frame = tile.bounds
        strike.path = line
        strikeHalo.frame = tile.bounds
        strikeHalo.path = line
        tile.layer?.shadowPath = CGPath(roundedRect: tile.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
        CATransaction.commit()
        toggle.frame = NSRect(x: card.bounds.width - 8 - 36, y: ((h - 22) / 2).rounded(), width: 36, height: 22)
        let x = tile.frame.maxX + 10
        let right = toggle.isHidden ? card.bounds.width - 8 : toggle.frame.minX - 8
        title.frame = NSRect(x: x - SidebarText.inset, y: 10, width: max(0, right - x) + 2 * SidebarText.inset, height: 18)
        detail.frame = NSRect(x: x - SidebarText.inset, y: 28, width: max(0, right - x) + 2 * SidebarText.inset, height: 16)
        editor?.frame = title.frame
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsLayout = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsLayout = true }
    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }
    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, editor == nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        open()
    }
}

/// Arc's switch on a boost row: a 36 × 22 pt capsule, the knob 18 pt, 2 pt in.
private final class BoostSwitch: NSView {
    var onFlip: () -> Void = {}
    private let knob = CALayer()
    private var on = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(knob)
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.2
        knob.shadowRadius = 1
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Boost on")
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(on: Bool, tint: NSColor, knob color: NSColor, ink: NSColor) {
        self.on = on
        layer?.backgroundColor = (on ? tint : ink.withAlphaComponent(0.16)).cgColor
        knob.backgroundColor = color.cgColor
        setAccessibilityValue(on)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let d = bounds.height - 4
        knob.cornerRadius = d / 2
        knob.frame = NSRect(x: on ? bounds.width - 2 - d : 2, y: 2, width: d, height: d)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onFlip() }
    }
    override func accessibilityPerformPress() -> Bool { onFlip(); return true }
}
