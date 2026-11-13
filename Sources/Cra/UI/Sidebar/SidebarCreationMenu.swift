import AppKit

/// The sidebar's menu + (Arc's PlusMenuIcon): two 2 pt round-capped strokes 14 pt end to end,
/// turned 45° into an × on a spring while the creation menu is open.
@MainActor
enum SidebarPlusMark {
    static let size = CGSize(width: 14, height: 14)
    static let lineWidth: CGFloat = 2

    static let path: CGPath = {
        let p = CGMutablePath()
        let r = lineWidth / 2
        p.move(to: CGPoint(x: r, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width - r, y: size.height / 2))
        p.move(to: CGPoint(x: size.width / 2, y: r)); p.addLine(to: CGPoint(x: size.width / 2, y: size.height - r))
        return p
    }()

    /// SwiftUI's spring(response: 0.2, dampingFraction: 0.5): stiffness (2π / response)², damping 4π · fraction / response.
    static func spring(from: CGFloat, to: CGFloat) -> CASpringAnimation {
        let a = CASpringAnimation(keyPath: "transform.rotation.z")
        a.mass = 1
        a.stiffness = pow(2 * .pi / 0.2, 2)
        a.damping = 4 * .pi * 0.5 / 0.2
        a.fromValue = from
        a.toValue = to
        a.duration = a.settlingDuration
        return a
    }

    /// Sets the layer's resting angle, then springs to it from where it is on screen.
    static func turn(_ layer: CALayer, open: Bool, animated: Bool) {
        let angle: CGFloat = open ? .pi / 4 : 0
        let from = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? (open ? 0 : .pi / 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        if animated { layer.add(spring(from: from, to: angle), forKey: "turn") } else { layer.removeAnimation(forKey: "turn") }
        CATransaction.commit()
    }
}

/// The menu's colours, from the space's dark semantic palette (CraCore ArcMenuTones).
struct SidebarCreationMenuColors {
    var fill = NSColor(srgbRed: 5 / 255, green: 6 / 255, blue: 39 / 255, alpha: 1)
    var hover = NSColor(srgbRed: 47 / 255, green: 51 / 255, blue: 145 / 255, alpha: 1)
    var separator = NSColor(srgbRed: 47 / 255, green: 51 / 255, blue: 145 / 255, alpha: 1)
    var shortcut = NSColor(srgbRed: 118 / 255, green: 119 / 255, blue: 128 / 255, alpha: 1)
    var disabled = NSColor(srgbRed: 121 / 255, green: 120 / 255, blue: 129 / 255, alpha: 1)
}

struct SidebarCreationMenuItem {
    let title: String
    let symbol: String
    let shortcut: String
    let enabled: Bool
    /// A page's favicon in place of the symbol: the back and forward list's rows (GitHub #416).
    var favicon: NSImage? = nil
    let action: () -> Void
}

@MainActor
final class SidebarCreationMenuController {
    private var panel: SidebarCreationMenuWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var onOpenChange: ((Bool) -> Void)?

    /// `anchorToggles`: a click on the anchor is left to it, the + button closing the menu it opened.
    /// Otherwise it closes the menu as any click outside does (Back still goes back).
    func toggle(from anchor: NSView, items: [SidebarCreationMenuItem], colors: SidebarCreationMenuColors = .init(),
                layout: ArcMenuLayout = SidebarCreationMenuView.plusLayout, width: CGFloat = SidebarCreationMenuView.plusWidth,
                picksLastRow: Bool = true, anchorToggles: Bool = true, onOpenChange: @escaping (Bool) -> Void) {
        if panel != nil { close(); return }
        guard let parent = anchor.window else { return }
        let menu = SidebarCreationMenuView(items: items, colors: colors, layout: layout, width: width, picksLastRow: picksLastRow) { [weak self] index in
            self?.close()
            if let index { items[index].action() }
        }
        let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? rect.insetBy(dx: -1000, dy: -1000)
        let size = menu.frame.size
        let x: CGFloat
        let y: CGFloat
        switch layout.tail {
        case .bottom:
            // Arc 1.172.1 (live, 9 Nov 2026): the button's centre 194 pt into the fill, the tail 3.5 pt left of
            // it, the tail's tip 10 pt above the button.
            x = min(max(rect.midX - Self.buttonCentre, screen.minX + 4), screen.maxX - size.width - 4)
            y = min(rect.maxY + 10, screen.maxY - size.height - 4)
            menu.arrowX = min(max(rect.midX - x - 3.5, 18), size.width - 18)
        case .top:
            // Arc 1.172.1's back list (2x capture, 13 Nov 2026, #416): centred on the button, the tail's
            // tip 27 pt under the arrow, as Arc's ••• popover hangs 10 pt under its 28 pt button: 8 pt
            // under Cra's 32 pt one (the arrow's ink sits 3 pt above the button's centre).
            x = min(max(rect.midX - size.width / 2, screen.minX + 4), screen.maxX - size.width - 4)
            y = max(rect.minY - 8 - size.height, screen.minY + 4)
            menu.arrowX = min(max(rect.midX - x, 18), size.width - 18)
        }
        let popup = SidebarCreationMenuWindow(contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
                                              styleMask: .borderless, backing: .buffered, defer: false)
        popup.backgroundColor = .clear
        popup.isOpaque = false
        popup.hasShadow = true
        popup.isReleasedWhenClosed = false
        popup.hidesOnDeactivate = false
        popup.animationBehavior = .default
        popup.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        popup.contentView = menu
        panel = popup
        self.onOpenChange = onOpenChange
        menu.layoutSubtreeIfNeeded()
        menu.animate(opening: true)
        parent.addChildWindow(popup, ordered: .above)
        popup.makeKeyAndOrderFront(nil)
        popup.makeFirstResponder(menu)
        onOpenChange(true)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self, weak popup] event in
            guard let self, let popup else { return event }
            if event.type == .keyDown {
                if menu.handleKey(event) { return nil }
                self.close()
            } else if event.window !== popup {
                let overAnchor = anchorToggles && event.type == .leftMouseDown && event.window === parent
                    && anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
                if overAnchor { return event }
                self.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.willMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(animated: false) }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    static let buttonCentre: CGFloat = 194

    func close(animated: Bool = true) {
        guard let popup = panel else { return }
        panel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        let parent = popup.parent
        let wasKey = popup.isKeyWindow
        popup.dismiss(animated: animated)
        if wasKey { parent?.makeKey() }
        onOpenChange?(false)
        onOpenChange = nil
    }
}

private final class SidebarCreationMenuWindow: NSWindow, CAAnimationDelegate {
    private var isDismissing = false

    override var canBecomeKey: Bool { !isDismissing }
    override var canBecomeMain: Bool { false }

    func dismiss(animated: Bool) {
        ignoresMouseEvents = true
        guard animated, let menu = contentView as? SidebarCreationMenuView, menu.layer != nil else {
            finishDismissal()
            return
        }
        isDismissing = true
        menu.animate(opening: false, delegate: self)
    }

    func animationDidStop(_ animation: CAAnimation, finished flag: Bool) {
        if isDismissing { finishDismissal() }
    }

    private func finishDismissal() {
        isDismissing = false
        contentView?.layer?.removeAnimation(forKey: "creationMenuTransform")
        contentView?.layer?.removeAnimation(forKey: "creationMenuOpacity")
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

@MainActor
final class SidebarCreationMenuView: NSView {
    /// New Space, New Folder | New Easel, New Boost | New Split, New Tab, the tail under them.
    nonisolated static let plusLayout = ArcMenuLayout(groups: [2, 2, 2], tail: .bottom)
    nonisolated static let plusWidth: CGFloat = 210
    /// The back and forward list's fill (Arc 1.172.1, 440 px in a 2x capture, GitHub #416).
    nonisolated static let listWidth: CGFloat = 220

    private let items: [SidebarCreationMenuItem]
    private let onPick: (Int?) -> Void
    private let layout: ArcMenuLayout
    private let colors: SidebarCreationMenuColors
    /// Arc opens the + menu with its last row (New Tab) picked, so Return makes a tab.
    private(set) var selected: Int? { didSet { needsDisplay = true } }
    private var pressed: Int?
    var arrowX: CGFloat = 190.5 { didSet { needsDisplay = true } }

    init(items: [SidebarCreationMenuItem], colors: SidebarCreationMenuColors = .init(), layout: ArcMenuLayout = SidebarCreationMenuView.plusLayout,
         width: CGFloat = SidebarCreationMenuView.plusWidth, picksLastRow: Bool = true, onPick: @escaping (Int?) -> Void) {
        self.items = items
        self.colors = colors
        self.layout = layout
        self.onPick = onPick
        selected = picksLastRow ? items.indices.last { items[$0].enabled } : nil
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: layout.height))
        wantsLayer = true
        setAccessibilityRole(.menu)
        for (index, item) in items.enumerated() {
            let row = NSButton(frame: rowRect(index))
            row.cell = SidebarCreationMenuCell(textCell: item.title)
            row.isBordered = false
            row.isEnabled = item.enabled
            row.setAccessibilityRole(.menuItem)
            row.setAccessibilityLabel(item.title)
            row.target = self
            row.action = #selector(choose(_:))
            row.tag = index
            let icon: NSImageView
            if let favicon = item.favicon {
                // Arc's 16 pt favicon, 16 pt into the fill.
                icon = NSImageView(frame: NSRect(x: 8, y: 12, width: 16, height: 16))
                icon.image = favicon
                // The globe a page without a favicon gets is a template: white, as the titles are.
                icon.contentTintColor = .white
            } else {
                icon = NSImageView(frame: NSRect(x: 9, y: 8, width: 24, height: 24))
                icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
                icon.contentTintColor = item.enabled ? .white : colors.disabled
            }
            icon.imageScaling = .scaleProportionallyDown
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
        guard let layer else { return }
        let x = arrowX - bounds.width * layer.anchorPoint.x
        // The tail's tip: under the fill, or above it on a list hung under its button.
        let y = layout.tail == .bottom ? bounds.height * (1 - layer.anchorPoint.y) : -bounds.height * layer.anchorPoint.y
        var small = CATransform3DMakeTranslation(x, y, 0)
        small = CATransform3DScale(small, 0.95, 0.95, 1)
        small = CATransform3DTranslate(small, -x, -y, 0)
        let oldScale = layer.animation(forKey: "creationMenuTransform") as? CABasicAnimation
        let oldFade = layer.animation(forKey: "creationMenuOpacity") as? CABasicAnimation
        let presented = layer.presentation()
        let fromTransform = presented?.transform ?? (oldScale?.fromValue as? NSValue)?.caTransform3DValue ?? layer.transform
        let fromOpacity = presented?.opacity ?? (oldFade?.fromValue as? NSNumber)?.floatValue ?? layer.opacity
        let targetTransform = opening ? CATransform3DIdentity : small
        let targetOpacity: Float = opening ? 1 : 0
        let timing = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: opening ? small : fromTransform)
        scale.toValue = NSValue(caTransform3D: targetTransform)
        scale.duration = opening ? 0.1 : 0.07
        scale.timingFunction = timing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opening ? 0 : fromOpacity
        fade.toValue = targetOpacity
        fade.duration = opening ? 0.05 : 0.07
        fade.timingFunction = timing
        fade.delegate = delegate
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        layer.opacity = targetOpacity
        layer.add(scale, forKey: "creationMenuTransform")
        layer.add(fade, forKey: "creationMenuOpacity")
        CATransaction.commit()
    }

    private func rowRect(_ index: Int) -> NSRect {
        NSRect(x: 8, y: layout.fillTop + layout.rowTops[index], width: bounds.width - 16, height: ArcMenuLayout.rowHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        colors.fill.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: layout.fillTop, width: bounds.width, height: layout.fillHeight), xRadius: 12, yRadius: 12).fill()
        // The tail starts 1 pt inside the fill.
        let base = layout.tail == .bottom ? layout.fillHeight - 1 : layout.fillTop + 1
        let tip = layout.tail == .bottom ? layout.height : 0
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: arrowX - 6, y: base))
        arrow.line(to: NSPoint(x: arrowX, y: tip))
        arrow.line(to: NSPoint(x: arrowX + 6, y: base))
        arrow.close()
        arrow.fill()
        if let selected {
            colors.hover.setFill()
            NSBezierPath(roundedRect: rowRect(selected), xRadius: 7, yRadius: 7).fill()
        }
        colors.separator.setFill()
        for y in layout.separatorTops {
            NSRect(x: 10, y: layout.fillTop + y, width: bounds.width - 20, height: 1).fill()
        }
        for (index, item) in items.enumerated() {
            let rect = rowRect(index)
            let ink = item.enabled ? NSColor.white : colors.disabled
            let shortcutInk = item.enabled ? colors.shortcut : colors.disabled
            let text = item.title as NSString
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink]
            let height = text.size(withAttributes: attributes).height
            if item.favicon == nil {
                text.draw(at: NSPoint(x: 50, y: rect.midY - height / 2), withAttributes: attributes)
            } else {
                // A page title's ink starts 41 pt into the fill (drawn from 40, as the + menu's 51 pt titles
                // are from 50) and is cut short with an ellipsis (Arc's capture, #416).
                let truncating = NSMutableParagraphStyle()
                truncating.lineBreakMode = .byTruncatingTail
                attributes[.paragraphStyle] = truncating
                text.draw(with: NSRect(x: 40, y: rect.midY - height / 2, width: rect.maxX - 8 - 40, height: height),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            }
            let shortcut = Self.shortcutText(item.shortcut) as NSString
            let shortcutAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: shortcutInk,
                                                                     .kern: 2.5]
            let size = shortcut.size(withAttributes: shortcutAttributes)
            // The kern also trails the last glyph; Arc's shortcuts end 21 pt from the edge.
            shortcut.draw(at: NSPoint(x: bounds.width - 21 - size.width + 2.5, y: rect.midY - size.height / 2), withAttributes: shortcutAttributes)
        }
    }

    /// Arc's menu shows the key equivalents of its main menu: ⌃⇧= reads "⌃+".
    static func shortcutText(_ display: String) -> String { display.replacingOccurrences(of: "⇧=", with: "+") }

    @objc private func choose(_ sender: NSButton) {
        if items[sender.tag].enabled { onPick(sender.tag) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func index(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return items.indices.first { items[$0].enabled && rowRect($0).contains(point) }
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
            let enabled = items.indices.filter { items[$0].enabled }
            guard !enabled.isEmpty else { return true }
            let step = event.keyCode == 125 ? 1 : -1
            let current = selected.flatMap { enabled.firstIndex(of: $0) } ?? (step == 1 ? -1 : 0)
            selected = enabled[(current + step + enabled.count) % enabled.count]
        default: return false
        }
        return true
    }
}

private final class SidebarCreationMenuCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
}
