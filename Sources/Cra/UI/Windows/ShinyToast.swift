import AppKit
import QuartzCore

/// Arc's toast (Toasts.ShinyToastView): every short confirmation in Arc is one, "New Tab Created"
/// (⌘Return in the command bar with the sidebar hidden, GitHub #85), "Copied Current URL",
/// "Cannot Add New Pane" and the rest (`backgroundTabCreated`, `copyTabURL`, `maxNumberPanes`…), so
/// Cra shows all of its confirmations with this. Arc 1.171, measured 2 Nov 2026 at 1x: a 42 pt pill 8 pt below the top of the
/// page and 9 pt in from its right edge, 14 pt medium black text with 12 pt either side, a fill
/// from the space's colours with a 1 pt darker outline. It springs in from its top centre
/// (≈0.3 s response, 4 % overshoot), stays 4.85 s after the last tab it announced (another one
/// bumps it by 4 %) and shrinks back into its top in 80 ms. Some of Arc's carry a button
/// ("Screenshot Copied to Clipboard" offers Save): a capsule after the text, and the toast stays
/// up while the pointer is on it.
@MainActor
final class ShinyToast {
    struct Action {
        let title: String
        let run: () -> Void
    }

    static let height: CGFloat = 42
    static let topInset: CGFloat = 8
    static let trailingInset: CGFloat = 9
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 10
    /// Room around the pill in its panel, so the spring's overshoot isn't clipped.
    static let margin: CGFloat = 8
    static let font = NSFont.systemFont(ofSize: 14, weight: .medium)
    /// How long the toast stays up after the last message.
    static let visibleFor: TimeInterval = 4.85
    static let buttonFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let buttonHeight: CGFloat = 26
    static let buttonPadding: CGFloat = 10
    /// Between the text and the button.
    static let buttonGap: CGFloat = 10

    private let panel: NSPanel
    private let view = ToastView()
    private let pill = CAGradientLayer()
    private let label = CATextLayer()
    private let button = CALayer()
    private let buttonLabel = CATextLayer()
    private var hide: DispatchWorkItem?
    private var action: Action?
    /// The text colour: the button is a wash of it.
    private var buttonTint = NSColor.black

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 140, height: Self.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        view.frame = panel.contentLayoutRect
        view.wantsLayer = true
        panel.contentView = view
        pill.cornerRadius = Self.cornerRadius
        pill.cornerCurve = .continuous
        pill.borderWidth = 1
        label.font = Self.font
        label.fontSize = Self.font.pointSize
        label.alignmentMode = .center
        label.foregroundColor = NSColor.black.cgColor
        pill.addSublayer(label)
        button.cornerRadius = Self.buttonHeight / 2
        button.cornerCurve = .continuous
        buttonLabel.font = Self.buttonFont
        buttonLabel.fontSize = Self.buttonFont.pointSize
        buttonLabel.alignmentMode = .center
        button.addSublayer(buttonLabel)
        pill.addSublayer(button)
        view.layer?.addSublayer(pill)
        view.onHover = { [weak self] inside in self?.hovered(inside) }
        view.onClick = { [weak self] point in self?.clicked(at: point) }
    }

    var isShown: Bool { panel.parent != nil }

    /// Shows `text` at the top right of `page` (window coordinates) over `window`'s pages.
    func show(_ text: String, action: Action? = nil, page: NSRect, in window: NSWindow, theme: SpaceTheme) {
        self.action = action
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width)
        let buttonWidth = action.map { ceil(($0.title as NSString).size(withAttributes: [.font: Self.buttonFont]).width) + 2 * Self.buttonPadding }
        let width = textWidth + 2 * Self.padding + (buttonWidth.map { $0 + Self.buttonGap - Self.padding + (Self.height - Self.buttonHeight) / 2 } ?? 0)
        let local = NSRect(x: page.maxX - Self.trailingInset - width, y: page.maxY - Self.topInset - Self.height,
                           width: width, height: Self.height)
        panel.setFrame(window.convertToScreen(local.insetBy(dx: -Self.margin, dy: -Self.margin)), display: false)
        let scale = window.backingScaleFactor
        let colors = Self.colors(theme)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Anchored at the top centre, where Arc's toast grows from.
        pill.anchorPoint = CGPoint(x: 0.5, y: 1)
        pill.bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        pill.position = CGPoint(x: Self.margin + width / 2, y: Self.margin + Self.height)
        // Top to bottom (a layer's y runs up).
        pill.colors = [colors.bottom.cgColor, colors.top.cgColor]
        pill.borderColor = colors.outline.cgColor
        label.foregroundColor = colors.text.cgColor
        label.contentsScale = scale
        label.string = text
        let lineHeight = ceil(Self.font.ascender - Self.font.descender)
        label.frame = CGRect(x: buttonWidth == nil ? 0 : Self.padding, y: (Self.height - lineHeight) / 2,
                             width: buttonWidth == nil ? width : textWidth, height: lineHeight)
        button.isHidden = buttonWidth == nil
        if let buttonWidth, let action {
            let inset = (Self.height - Self.buttonHeight) / 2
            button.frame = CGRect(x: width - inset - buttonWidth, y: inset, width: buttonWidth, height: Self.buttonHeight)
            buttonTint = colors.text
            button.backgroundColor = colors.text.withAlphaComponent(0.1).cgColor
            buttonLabel.foregroundColor = colors.text.cgColor
            buttonLabel.contentsScale = scale
            buttonLabel.string = action.title
            let buttonLine = ceil(Self.buttonFont.ascender - Self.buttonFont.descender)
            buttonLabel.frame = CGRect(x: 0, y: (Self.buttonHeight - buttonLine) / 2, width: buttonWidth, height: buttonLine)
        }
        CATransaction.commit()
        panel.ignoresMouseEvents = action == nil
        view.hitRect = action == nil ? .zero : NSRect(x: Self.margin, y: Self.margin, width: width, height: Self.height)
        if !isShown {
            // Opening the tab's page holds the main thread for ~0.1 s, so the toast waits for the
            // next turn, invisible: started now, its first frame showed it most of the way in.
            setOpacity(0)
            window.addChildWindow(panel, ordered: .above)
            DispatchQueue.main.async { [weak self] in self?.springIn() }
        } else {
            if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
            setOpacity(1)
            // Another message while it is up: Arc bumps it (1 → 1.044 → 1 in ~0.2 s) and restarts its time.
            DispatchQueue.main.async { [weak self] in self?.pulse() }
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    /// The pointer on a toast with a button holds it up; leaving starts its time again.
    private func hovered(_ inside: Bool) {
        guard isShown, action != nil else { return }
        if inside {
            hide?.cancel()
        } else if hide?.isCancelled != false {
            scheduleHide()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        button.backgroundColor = buttonTint.withAlphaComponent(inside ? 0.16 : 0.1).cgColor
        CATransaction.commit()
    }

    /// `point` in the content view: the button runs its action and the toast goes.
    private func clicked(at point: NSPoint) {
        guard let action, isShown else { return }
        let local = NSPoint(x: point.x - Self.margin, y: point.y - Self.margin)
        guard button.frame.insetBy(dx: -4, dy: -4).contains(local) else { return }
        dismiss()
        action.run()
    }

    private func springIn() {
        guard isShown else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.4
        spring.toValue = 1
        // ω = 2π / 0.3 s, damping ratio 0.67: Arc's 4 % overshoot ~0.2 s in, settled by 0.4 s.
        spring.mass = 1
        spring.stiffness = 440
        spring.damping = 28
        spring.duration = spring.settlingDuration
        // A new child window reaches the screen a frame or two late; hold the start until then.
        // No fade: Arc's first frame is the small pill at full colour (0.41 of its width).
        spring.beginTime = CACurrentMediaTime() + 0.03
        spring.fillMode = .backwards
        pill.add(spring, forKey: "appear")
        setOpacity(1)
    }

    private func pulse() {
        let bump = CAKeyframeAnimation(keyPath: "transform.scale")
        bump.values = [1, 1.044, 1]
        bump.keyTimes = [0, 0.2, 1]
        bump.duration = 0.21
        bump.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pill.add(bump, forKey: "appear")
    }

    /// The model value only; the explicit animations above are the ones that show.
    private func setOpacity(_ value: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.opacity = value
        CATransaction.commit()
    }

    func dismiss() {
        hide?.cancel()
        hide = nil
        guard isShown else { return }
        panel.ignoresMouseEvents = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hide == nil else { return }
                self.panel.parent?.removeChildWindow(self.panel)
                self.panel.orderOut(nil)
            }
        }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = 0.08
        pill.add(group, forKey: "fade")
        setOpacity(0)
        CATransaction.commit()
    }

    /// Arc builds it from the space's background (ShinyToastBackgroundBasedPalette): the theme's hue,
    /// pale with black text on a light theme, deep with white text on a dark one, a little darker
    /// at the bottom, outlined darker still. Fitted to one Arc theme of each kind (2 Nov 2026, sRGB):
    /// light (Victor's yellow/green) 220/226/184 → 208/218/163, outline 151/157/124; dark (the
    /// default theme in dark mode) 43/24/102 → 33/19/79, outline 26/15/62, white text.
    static func colors(_ theme: SpaceTheme) -> (top: NSColor, bottom: NSColor, outline: NSColor, text: NSColor) {
        let comps = theme.colors.compactMap(HexColor.components)
        let n = Double(max(comps.count, 1))
        let mean = NSColor(srgbRed: comps.reduce(0) { $0 + $1.r } / n, green: comps.reduce(0) { $0 + $1.g } / n,
                           blue: comps.reduce(0) { $0 + $1.b } / n, alpha: 1)
        let hue = mean.hueComponent, sat = comps.isEmpty ? 0 : mean.saturationComponent
        func color(_ s: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(hue: hue, saturation: s, brightness: b, alpha: 1).usingColorSpace(.sRGB) ?? .gray
        }
        if theme.isDark {
            let s = min(0.76, sat * 1.9)
            let top = color(s, 0.40)
            return (top, color(s, 0.31), color(s, 0.24), .white)
        }
        let s = min(0.19, sat * 0.3)
        let top = color(s, 0.89)
        return (top, color(min(0.25, s * 1.3), 0.85), color(s, 0.61), .black)
    }
}

/// The toast's content: tracks the pointer over the pill and takes the click on its button
/// without making Cra active first.
private final class ToastView: NSView {
    var hitRect: NSRect = .zero { didSet { updateTrackingAreas() } }
    var onHover: (Bool) -> Void = { _ in }
    var onClick: (NSPoint) -> Void = { _ in }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        guard !hitRect.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: hitRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick(convert(event.locationInWindow, from: nil)) }
}
