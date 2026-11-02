import AppKit
import QuartzCore

/// Arc's "New Tab Created" toast (Toasts.ShinyToastView, the `backgroundTabCreated` toast), shown
/// when ⌘Return in the command bar opens a tab the sidebar can't show because it is hidden
/// (GitHub #85). Arc 1.171, measured 2 Nov 2026 at 1x: a 42 pt pill 8 pt below the top of the
/// page and 9 pt in from its right edge, 14 pt medium black text with 12 pt either side, a fill
/// from the space's colours with a 1 pt darker outline. It springs in from its top centre
/// (≈0.3 s response, 4 % overshoot), stays 4.85 s and shrinks back into its top in 80 ms.
@MainActor
final class BackgroundTabToast {
    static let height: CGFloat = 42
    static let topInset: CGFloat = 8
    static let trailingInset: CGFloat = 9
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 10
    /// Room around the pill in its panel, so the spring's overshoot isn't clipped.
    static let margin: CGFloat = 8
    static let font = NSFont.systemFont(ofSize: 14, weight: .medium)
    /// How long the toast stays up after the last tab it announced.
    static let visibleFor: TimeInterval = 4.85

    private let panel: NSPanel
    private let pill = CALayer()
    private let label = CATextLayer()
    private var hide: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 140, height: Self.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let view = NSView(frame: panel.contentLayoutRect)
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
        view.layer?.addSublayer(pill)
    }

    var isShown: Bool { panel.parent != nil }

    /// Shows `text` at the top right of `page` (window coordinates) over `window`'s pages.
    func show(_ text: String, page: NSRect, in window: NSWindow, theme: SpaceTheme) {
        let width = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 2 * Self.padding
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
        pill.backgroundColor = colors.fill.cgColor
        pill.borderColor = colors.outline.cgColor
        label.contentsScale = scale
        label.string = text
        let lineHeight = ceil(Self.font.ascender - Self.font.descender)
        label.frame = CGRect(x: 0, y: (Self.height - lineHeight) / 2, width: width, height: lineHeight)
        CATransaction.commit()
        if !isShown {
            // Opening the tab's page holds the main thread for ~0.1 s, so the toast waits for the
            // next turn, invisible: started now, its first frame showed it most of the way in.
            setOpacity(0)
            window.addChildWindow(panel, ordered: .above)
            DispatchQueue.main.async { [weak self] in self?.springIn() }
        } else {
            if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
            setOpacity(1)
        }
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
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

    /// Arc builds it from the window's background (ShinyToastBackgroundBasedPalette). Fitted to one
    /// theme (a yellow/green one, fill ≈ 214/222/174 sRGB mid-height): the theme colours' mean 70 %
    /// of the way to white, 8 % darker, and the outline at 69 % of that.
    static func colors(_ theme: SpaceTheme) -> (fill: NSColor, outline: NSColor) {
        let comps = theme.colors.compactMap(HexColor.components)
        guard !comps.isEmpty else { return (NSColor(white: 0.9, alpha: 1), NSColor(white: 0.62, alpha: 1)) }
        let n = Double(comps.count)
        func channel(_ v: Double) -> Double { (v / n + (1 - v / n) * 0.7) * 0.92 }
        let r = channel(comps.reduce(0) { $0 + $1.r }), g = channel(comps.reduce(0) { $0 + $1.g }), b = channel(comps.reduce(0) { $0 + $1.b })
        return (NSColor(srgbRed: r, green: g, blue: b, alpha: 1), NSColor(srgbRed: r * 0.69, green: g * 0.69, blue: b * 0.69, alpha: 1))
    }
}
