import AppKit
import QuartzCore

/// An MCP agent's pill at the bottom of the page while it acts (Victor's design, 17 Nov 2026):
/// a dark capsule with the agent's face, what it is doing ("Claude Code is clicking “Compare”",
/// MCPAgentPresence) and Take Over with its keys, ⌘ and . — ⌘. or a click ends the agent's session.
/// A new step changes the words in place: the old ones rise and fade, the new ones come up from
/// below, the capsule eases to its new width and the face blinks. It stays up while the agent
/// works (and while the pointer is on it) and goes `lingers` after the last step (Settings ▸
/// Advanced ▸ Agents, discussion #862).
///
/// While the agent acts in a tab the user isn't looking at, the pill is only the agent's face,
/// still, where the pill would be (MCPAgentPresence.pillLook, discussion #579): no words, no
/// blinking. A click on the face opens the whole pill; ⌘. takes over either way. The whole pill
/// shows a × on hover, as macOS's notifications do: the pill goes until the agent's session ends,
/// and the agent keeps working.
@MainActor
final class AgentPill {
    static let height: CGFloat = 46
    static let bottomInset: CGFloat = 28
    /// Room around the capsule in its panel for the shadow and the way in.
    static let margin: CGFloat = 24
    static let radius: CGFloat = 18
    static let leading: CGFloat = 13
    static let faceSide: CGFloat = 22
    static let faceGap: CGFloat = 11
    static let textGap: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: 14.5)
    static let capFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// The button sits 5 pt in from the capsule's top, bottom and end.
    static let buttonInset: CGFloat = 5
    static let buttonPadding: CGFloat = 12
    static let capSide: CGFloat = 26
    static let capGap: CGFloat = 4
    static let capsLead: CGFloat = 9
    /// The face alone: the capsule shrunk to the face with the same room on both sides.
    static let faceWidth: CGFloat = 2 * leading + faceSide
    static let closeSide: CGFloat = 18
    /// The ×'s middle, in from the capsule's top left corner.
    static let closeInset: CGFloat = 4
    static let takeOverTitle = "Take Over"
    static let background = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.125, alpha: 1)

    private let panel: NSPanel
    private let view = AgentPillView()
    private let pill = CALayer()
    /// Clips the words while they change (the old ones may be wider than the new capsule).
    private let clip = CALayer()
    private let face = AgentFaceLayer()
    private var label: CATextLayer?
    private let button = CALayer()
    private let buttonLabel = CATextLayer()
    private let caps = [CALayer(), CALayer()]
    private let capLabels = [CATextLayer(), CATextLayer()]
    private let closeButton = CALayer()
    private let closeGlyph = CAShapeLayer()
    private(set) var text = ""
    private(set) var look: MCPAgentPresence.PillLook = .full
    /// The user clicked the face: the whole pill until it goes.
    private var opened = false
    private var lingers: TimeInterval = MCPAgentPresence.Linger.standard.seconds
    private var takeOver: (() -> Void)?
    private var close: (() -> Void)?
    private var page: (() -> NSRect?)?
    private var hide: DispatchWorkItem?
    /// When the shown words came in, and newer words waiting for them to have shown long enough
    /// (MCPAgentPresence.pillHold); only the latest waits.
    private var shownAt: CFTimeInterval = 0
    private var waiting: DispatchWorkItem?
    private var resize: NSObjectProtocol?
    private var pointerInside = false

    private static let showing = NSHashTable<NSPanel>.weakObjects()

    /// The pills' panels over `window`, for the window's ordering of its child panels.
    static func panels(over window: NSWindow) -> [NSPanel] {
        showing.allObjects.filter { $0.parent === window && $0.isVisible }
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        view.wantsLayer = true
        panel.contentView = view
        pill.backgroundColor = Self.background.cgColor
        pill.cornerRadius = Self.radius
        pill.cornerCurve = .continuous
        pill.borderWidth = 1
        pill.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.28
        pill.shadowRadius = 14
        pill.shadowOffset = CGSize(width: 0, height: -8)
        clip.masksToBounds = true
        clip.cornerRadius = Self.radius
        clip.cornerCurve = .continuous
        pill.addSublayer(clip)
        pill.addSublayer(face)
        button.cornerRadius = 13
        button.cornerCurve = .continuous
        button.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        buttonLabel.string = Self.takeOverTitle
        buttonLabel.font = Self.font
        buttonLabel.fontSize = Self.font.pointSize
        buttonLabel.foregroundColor = NSColor.white.cgColor
        button.addSublayer(buttonLabel)
        for (cap, (capLabel, key)) in zip(caps, zip(capLabels, ["⌘", "."])) {
            cap.cornerRadius = 7
            cap.cornerCurve = .continuous
            cap.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            capLabel.string = key
            capLabel.font = Self.capFont
            capLabel.fontSize = Self.capFont.pointSize
            capLabel.alignmentMode = .center
            capLabel.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            cap.addSublayer(capLabel)
            button.addSublayer(cap)
        }
        pill.addSublayer(button)
        closeButton.bounds = CGRect(x: 0, y: 0, width: Self.closeSide, height: Self.closeSide)
        closeButton.cornerRadius = Self.closeSide / 2
        closeButton.backgroundColor = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.25, alpha: 1).cgColor
        closeButton.borderWidth = 1
        closeButton.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        closeButton.shadowColor = NSColor.black.cgColor
        closeButton.shadowOpacity = 0.25
        closeButton.shadowRadius = 3
        closeButton.shadowOffset = CGSize(width: 0, height: -1)
        let glyph = CGMutablePath(), a: CGFloat = 6, b = Self.closeSide - 6
        glyph.move(to: CGPoint(x: a, y: a)); glyph.addLine(to: CGPoint(x: b, y: b))
        glyph.move(to: CGPoint(x: a, y: b)); glyph.addLine(to: CGPoint(x: b, y: a))
        closeGlyph.frame = closeButton.bounds
        closeGlyph.path = glyph
        closeGlyph.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        closeGlyph.lineWidth = 1.5
        closeGlyph.lineCap = .round
        closeButton.addSublayer(closeGlyph)
        closeButton.opacity = 0
        closeButton.zPosition = 1
        pill.addSublayer(closeButton)
        pill.opacity = 0
        view.layer?.addSublayer(pill)
        view.onHover = { [weak self] inside in self?.hovered(inside) }
        view.onMove = { [weak self] point in self?.moved(to: point) }
        view.onClick = { [weak self] point in self?.clicked(at: point) }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
    }

    var isShown: Bool { panel.parent != nil }

    private static func measure(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static var buttonWidth: CGFloat {
        buttonPadding + measure(takeOverTitle, font) + capsLead + 2 * capSide + capGap + (height - 2 * buttonInset - capSide) / 2
    }

    /// The capsule's width for `textWidth`, and the words' width cut to fit a page `available` wide.
    private static func widths(text: String, available: CGFloat) -> (pill: CGFloat, text: CGFloat) {
        let fixed = leading + faceSide + faceGap + textGap + buttonWidth + buttonInset
        let text = min(measure(text, font), max(80, available - 40 - fixed))
        return (fixed + text, text)
    }

    /// Shows `text` over the bottom middle of `page()` (window coordinates; asked again as the
    /// window resizes), whole while the agent acts in a tab the user is looking at (`tabWatched`),
    /// else its face alone; it goes `lingers` after the last call. `takeOver` runs on the button or
    /// ⌘., once; `close` on the ×.
    func show(_ text: String, tabWatched: Bool, lingers: TimeInterval, page: @escaping () -> NSRect?, in window: NSWindow,
              takeOver: @escaping () -> Void, close: @escaping () -> Void) {
        self.takeOver = takeOver
        self.close = close
        self.page = page
        self.lingers = lingers
        guard let frame = page() else { return }
        let first = !isShown || pill.opacity == 0
        if first { opened = false }
        place(frame, in: window)
        let scale = window.backingScaleFactor
        let sizes = Self.widths(text: text, available: frame.width)
        let wanted = MCPAgentPresence.pillLook(tabWatched: tabWatched, opened: opened)
        if first {
            look = wanted
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layout(width: width(sizes), scale: scale)
            label?.removeFromSuperlayer()
            label = makeLabel(text, width: sizes.text, scale: scale)
            clip.addSublayer(label!)
            showParts()
            pill.opacity = 1
            CATransaction.commit()
            appear()
            if look == .full { face.startBlinking() }
            CraLog.note("mcp pill look: \(look == .full ? "full" : "face")")
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue])
            waiting?.cancel()
            waiting = nil
            shownAt = CACurrentMediaTime()
            self.text = text
            view.setAccessibilityLabel(text)
            CraLog.note("mcp pill shows: \(text)")
        } else {
            // The user went to the agent's tab, or away from it: the pill grows or shrinks first.
            if wanted != look {
                look = wanted
                morph(text: text, available: frame.width, scale: scale)
            }
            guard text != self.text else {
                waiting?.cancel()
                waiting = nil
                return finishShow(in: window)
            }
            let wait = MCPAgentPresence.pillWait(shownFor: CACurrentMediaTime() - shownAt)
            waiting?.cancel()
            waiting = nil
            if wait == 0 {
                swap(to: text, sizes: sizes, scale: scale)
            } else {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isShown, self.pill.opacity > 0, let window = self.panel.parent, let frame = self.page?() else { return }
                        self.waiting = nil
                        self.swap(to: text, sizes: Self.widths(text: text, available: frame.width), scale: window.backingScaleFactor)
                    }
                }
                waiting = work
                DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
            }
        }
        finishShow(in: window)
    }

    private func finishShow(in window: NSWindow) {
        if resize == nil {
            resize = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.panel.parent, let frame = self.page?() else { return }
                    self.place(frame, in: window)
                }
            }
        }
        scheduleHide()
    }

    /// The panel along the bottom of the page, the capsule in its middle.
    private func place(_ page: NSRect, in window: NSWindow) {
        let local = NSRect(x: page.minX, y: page.minY, width: page.width, height: Self.bottomInset + Self.height + Self.margin)
        panel.setFrame(window.convertToScreen(local), display: false)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            Self.showing.add(panel)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.position = CGPoint(x: (local.width / 2).rounded(), y: Self.bottomInset + Self.height / 2)
        // The window is being resized: the capsule fits the page as it goes, the words cut short
        // with an ellipsis rather than the capsule running off the page's edges.
        if let label, !text.isEmpty, label.animation(forKey: "in") == nil {
            let sizes = Self.widths(text: text, available: page.width)
            if abs(pill.bounds.width - width(sizes)) > 0.5 {
                layout(width: width(sizes), scale: window.backingScaleFactor)
                label.frame.size.width = sizes.text + 2
            }
        }
        CATransaction.commit()
        updateHitRects()
    }

    /// The capsule's parts for `width` (inside an animation when one is open).
    private func layout(width: CGFloat, scale: CGFloat) {
        let h = Self.height
        pill.bounds = CGRect(x: 0, y: 0, width: width, height: h)
        clip.frame = pill.bounds
        if face.side != Self.faceSide || face.contentsScale != scale {
            face.configure(side: Self.faceSide, fill: Self.background, eyes: .white, outline: .white, scale: scale)
        }
        face.position = CGPoint(x: Self.leading + Self.faceSide / 2, y: h / 2)
        closeButton.position = CGPoint(x: Self.closeInset, y: h - Self.closeInset)
        let bw = Self.buttonWidth, bh = h - 2 * Self.buttonInset
        button.bounds = CGRect(x: 0, y: 0, width: bw, height: bh)
        button.position = CGPoint(x: width - Self.buttonInset - bw / 2, y: h / 2)
        let line = ceil(Self.font.ascender - Self.font.descender)
        buttonLabel.contentsScale = scale
        buttonLabel.frame = CGRect(x: Self.buttonPadding, y: (bh - line) / 2, width: Self.measure(Self.takeOverTitle, Self.font) + 2, height: line)
        let capInset = (bh - Self.capSide) / 2
        let capLine = ceil(Self.capFont.ascender - Self.capFont.descender)
        for (index, (cap, capLabel)) in zip(caps, capLabels).enumerated() {
            let x = bw - capInset - CGFloat(2 - index) * Self.capSide - CGFloat(1 - index) * Self.capGap
            cap.frame = CGRect(x: x, y: capInset, width: Self.capSide, height: Self.capSide)
            capLabel.contentsScale = scale
            capLabel.frame = CGRect(x: 0, y: (Self.capSide - capLine) / 2, width: Self.capSide, height: capLine)
        }
    }

    private func makeLabel(_ text: String, width: CGFloat, scale: CGFloat) -> CATextLayer {
        let l = CATextLayer()
        l.string = text
        l.font = Self.font
        l.fontSize = Self.font.pointSize
        l.foregroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        l.truncationMode = .end
        l.contentsScale = scale
        let line = ceil(Self.font.ascender - Self.font.descender)
        l.frame = CGRect(x: Self.leading + Self.faceSide + Self.faceGap, y: (Self.height - line) / 2, width: width + 2, height: line)
        return l
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The way in: up a little from below, fading in, on a soft spring.
    private func appear() {
        let rise = CASpringAnimation(keyPath: "transform.translation.y")
        rise.fromValue = reduceMotion ? 0 : -14
        rise.toValue = 0
        rise.mass = 1
        rise.stiffness = 300
        rise.damping = 26
        rise.duration = rise.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        pill.add(rise, forKey: "rise")
        pill.add(fade, forKey: "fade")
    }

    private func swap(to text: String, sizes: (pill: CGFloat, text: CGFloat), scale: CGFloat) {
        change(to: text, sizes: sizes, scale: scale)
        CraLog.note("mcp pill shows: \(text)")
        shownAt = CACurrentMediaTime()
        self.text = text
        view.setAccessibilityLabel(text)
    }

    /// New words: the old rise and fade, the new come up into place a moment later, and the
    /// capsule (with its button) eases to the new width around its middle.
    private func change(to text: String, sizes: (pill: CGFloat, text: CGFloat), scale: CGFloat) {
        let slide: CGFloat = reduceMotion ? 0 : 8
        let old = label
        // Words still leaving from an earlier change go now, so never more than two lines overlap.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for leftover in clip.sublayers ?? [] where leftover is CATextLayer && leftover !== old { leftover.removeFromSuperlayer() }
        let new = makeLabel(text, width: sizes.text, scale: scale)
        clip.addSublayer(new)
        CATransaction.commit()
        label = new

        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0.2 : 0.38)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        layout(width: width(sizes), scale: scale)
        CATransaction.commit()

        if let old {
            CATransaction.begin()
            CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
            // From where it is: words still coming in fade from there, not from full.
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = old.presentation()?.opacity ?? 1
            out.toValue = 0
            old.removeAnimation(forKey: "in")
            let up = CABasicAnimation(keyPath: "transform.translation.y")
            up.fromValue = 0
            up.toValue = slide
            let group = CAAnimationGroup()
            group.animations = [out, up]
            group.duration = 0.2
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            old.add(group, forKey: "out")
            CATransaction.commit()
        }
        let into = CABasicAnimation(keyPath: "opacity")
        into.fromValue = 0
        into.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -slide
        rise.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [into, rise]
        group.duration = 0.32
        group.beginTime = CACurrentMediaTime() + 0.07
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        new.add(group, forKey: "in")
        // The face alone stays still: the words change out of sight, ready for a click on it.
        if look == .full { face.blink() }
        updateHitRects()
    }

    /// The capsule's width for the look: the face alone, or the words and Take Over.
    private func width(_ sizes: (pill: CGFloat, text: CGFloat)) -> CGFloat { look == .face ? Self.faceWidth : sizes.pill }

    /// The words and Take Over show with the whole pill and hide with the face alone (inside an
    /// animation when one is open).
    private func showParts() {
        let whole: Float = look == .full ? 1 : 0
        clip.opacity = whole
        button.opacity = whole
        if look == .face { closeButton.opacity = 0 }
        updateAccessibility()
    }

    /// From the face alone to the whole pill or back: the capsule eases to its width around its
    /// middle as the words and Take Over fade in or out.
    private func morph(text: String, available: CGFloat, scale: CGFloat) {
        let sizes = Self.widths(text: self.text.isEmpty ? text : self.text, available: available)
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0.2 : 0.38)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        layout(width: width(sizes), scale: scale)
        label?.frame.size.width = sizes.text + 2
        showParts()
        CATransaction.commit()
        if look == .full { face.startBlinking(); face.blink() } else { face.stopBlinking() }
        if look == .full && pointerInside { setClose(visible: true) }
        updateHitRects()
        CraLog.note("mcp pill look: \(look == .full ? "full" : "face")")
    }

    /// A click on the face alone (or cra://debug?mcpPill=open): the whole pill until it goes.
    func open() {
        guard isShown, pill.opacity > 0, look == .face, let window = panel.parent, let frame = page?() else { return }
        CraLog.note("mcp pill: opened from the face")
        opened = true
        look = .full
        morph(text: text, available: frame.width, scale: window.backingScaleFactor)
    }

    /// The × (or cra://debug?mcpPill=close): away until the agent's session ends; it keeps working.
    func pressClose() {
        guard isShown, pill.opacity > 0, look == .full, let run = close else { return }
        close = nil
        run()
        dismiss()
    }

    private func setClose(visible: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        closeButton.opacity = visible ? 1 : 0
        CATransaction.commit()
    }

    private func updateAccessibility() {
        let actions: [NSAccessibilityCustomAction]
        switch look {
        case .full:
            actions = [NSAccessibilityCustomAction(name: Self.takeOverTitle) { [weak self] in self?.takeOverIfUp() ?? false },
                       NSAccessibilityCustomAction(name: "Hide") { [weak self] in self?.pressClose(); return true }]
        case .face:
            actions = [NSAccessibilityCustomAction(name: "Show") { [weak self] in self?.open(); return true }]
        }
        view.setAccessibilityCustomActions(actions)
    }

    private func scheduleHide() {
        hide?.cancel()
        guard !pointerInside else { hide = nil; return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lingers, execute: work)
    }

    /// ⌘. while the pill is up in its window (CraWindow.sendEvent), or View ▸ Stop Loading chosen
    /// then (AppDelegate "stop"): Take Over, as the button does.
    static func isTakeOverKey(_ event: NSEvent) -> Bool {
        let held = event.modifierFlags
        return event.type == .keyDown && MCPAgentPresence.isTakeOverKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                                                     command: held.contains(.command), shift: held.contains(.shift),
                                                                     option: held.contains(.option), control: held.contains(.control))
    }

    func takeOverIfUp() -> Bool {
        guard isShown, pill.opacity > 0, takeOver != nil else { return false }
        pressTakeOver()
        return true
    }

    private func pressTakeOver() {
        let run = takeOver
        takeOver = nil
        let flash = CAKeyframeAnimation(keyPath: "transform.scale")
        flash.values = [1, 0.94, 1]
        flash.duration = 0.16
        button.add(flash, forKey: "press")
        CraLog.note("mcp pill: Take Over")
        run?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.dismiss() }
    }

    private func hovered(_ inside: Bool) {
        pointerInside = inside
        if inside { hide?.cancel(); hide = nil } else if isShown { scheduleHide() }
        if !inside { setButtonFill(0.1) }
        setClose(visible: inside && look == .full && close != nil)
    }

    private func moved(to point: NSPoint) {
        guard look == .full else { return }
        setButtonFill(buttonRect().insetBy(dx: -2, dy: -2).contains(point) ? 0.17 : 0.1)
        let onClose = closeRect().insetBy(dx: -3, dy: -3).contains(point)
        closeButton.backgroundColor = NSColor(srgbRed: onClose ? 0.32 : 0.24, green: onClose ? 0.32 : 0.24, blue: onClose ? 0.33 : 0.25, alpha: 1).cgColor
    }

    private func setButtonFill(_ alpha: CGFloat) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        button.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        CATransaction.commit()
    }

    private func clicked(at point: NSPoint) {
        if look == .face { return open() }
        if closeRect().insetBy(dx: -3, dy: -3).contains(point) { return pressClose() }
        guard buttonRect().insetBy(dx: -4, dy: -4).contains(point) else { return }
        pressTakeOver()
    }

    /// In the panel's view, from the model values (where the capsule ends up).
    private func pillRect() -> NSRect {
        NSRect(x: pill.position.x - pill.bounds.width / 2, y: pill.position.y - pill.bounds.height / 2, width: pill.bounds.width, height: pill.bounds.height)
    }

    private func buttonRect() -> NSRect {
        let p = pillRect()
        return NSRect(x: p.minX + button.position.x - button.bounds.width / 2, y: p.minY + button.position.y - button.bounds.height / 2,
                      width: button.bounds.width, height: button.bounds.height)
    }

    private func closeRect() -> NSRect {
        let p = pillRect(), side = Self.closeSide
        return NSRect(x: p.minX + Self.closeInset - side / 2, y: p.maxY - Self.closeInset - side / 2, width: side, height: side)
    }

    /// The capsule, and with the whole pill its × (which sticks out past the corner).
    private func updateHitRects() {
        guard pill.opacity > 0 else { view.hitRect = .zero; return }
        view.hitRect = look == .full ? pillRect().union(closeRect()) : pillRect()
    }

    func dismiss() {
        hide?.cancel()
        waiting?.cancel()
        waiting = nil
        hide = nil
        takeOver = nil
        close = nil
        opened = false
        pointerInside = false
        closeButton.opacity = 0
        if let resize { NotificationCenter.default.removeObserver(resize) }
        resize = nil
        face.stopBlinking()
        text = ""
        guard isShown else { return }
        view.hitRect = .zero
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pill.opacity == 0 else { return }
                Self.showing.remove(self.panel)
                self.panel.parent?.removeChildWindow(self.panel)
                self.panel.orderOut(nil)
            }
        }
        let fall = CABasicAnimation(keyPath: "transform.translation.y")
        fall.fromValue = 0
        fall.toValue = reduceMotion ? 0 : -10
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fall, fade]
        group.duration = 0.18
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        pill.add(group, forKey: "leave")
        CATransaction.setDisableActions(true)
        pill.opacity = 0
        CATransaction.commit()
    }
}

/// The pill's panel content: tracks the pointer over the capsule and takes the click on its
/// button without making Cra active first; elsewhere clicks go through to the page.
private final class AgentPillView: NSView {
    var hitRect: NSRect = .zero { didSet { if hitRect != oldValue { updateTrackingAreas() } } }
    var onHover: (Bool) -> Void = { _ in }
    var onMove: (NSPoint) -> Void = { _ in }
    var onClick: (NSPoint) -> Void = { _ in }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        guard !hitRect.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: hitRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseMoved(with event: NSEvent) { onMove(convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick(convert(event.locationInWindow, from: nil)) }
}
