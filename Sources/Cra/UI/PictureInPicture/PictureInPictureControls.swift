import AppKit

/// Arc's Picture in Picture hover controls, drawn over the video.
///
/// Invisible until the pointer enters the window, then fades in a dark scrim
/// with the buttons: close (top-left) and back-to-tab (top-right), play/pause
/// in the middle between ±15 s skips. Fades out when the pointer leaves or
/// rests for a while. Only the buttons take clicks; everything else passes
/// through to the overlay, which drags and resizes the window.
@MainActor
final class PictureInPictureControlsView: NSView {
    var isPlaying = false { didSet { playButton.symbol = isPlaying ? "pause.fill" : "play.fill"; playButton.tip = isPlaying ? "Pause" : "Play" } }

    private let scrim = CAGradientLayer()
    private let closeButton = PictureInPictureButton(symbol: "xmark", pointSize: 12, diameter: 26, tip: "Close")
    private let backButton = PictureInPictureButton(symbol: "pip.exit", pointSize: 13, diameter: 26, tip: "Back to Tab")
    private let playButton = PictureInPictureButton(symbol: "play.fill", pointSize: 22, diameter: 48, tip: "Play")
    private let skipBackButton = PictureInPictureButton(symbol: "gobackward.15", pointSize: 17, diameter: 38, tip: "Skip back 15 seconds")
    private let skipAheadButton = PictureInPictureButton(symbol: "goforward.15", pointSize: 17, diameter: 38, tip: "Skip ahead 15 seconds")
    private var buttons: [PictureInPictureButton] { [closeButton, backButton, playButton, skipBackButton, skipAheadButton] }
    private var hideTimer: Timer?
    private var shown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
        scrim.colors = [NSColor.black.withAlphaComponent(0.45).cgColor,
                        NSColor.black.withAlphaComponent(0.15).cgColor,
                        NSColor.black.withAlphaComponent(0.15).cgColor,
                        NSColor.black.withAlphaComponent(0.45).cgColor]
        scrim.locations = [0, 0.3, 0.7, 1]
        layer?.addSublayer(scrim)
        for b in buttons {
            addSubview(b)
            b.onPress = { [weak self] in self?.show() }
        }
        closeButton.onClick = { PictureInPictureChrome.shared.actions?.close() }
        backButton.onClick = { PictureInPictureChrome.shared.actions?.backToTab() }
        playButton.onClick = { [weak self] in
            PictureInPictureChrome.shared.actions?.togglePlayback()
            self?.isPlaying.toggle()   // optimistic; the page confirms through didChangePictureInPicturePlayback
        }
        skipBackButton.onClick = { PictureInPictureChrome.shared.actions?.skip(-15) }
        skipAheadButton.onClick = { PictureInPictureChrome.shared.actions?.skip(15) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrim.frame = bounds
        CATransaction.commit()
        let inset: CGFloat = 10
        closeButton.setFrameOrigin(NSPoint(x: inset, y: inset))
        backButton.setFrameOrigin(NSPoint(x: bounds.maxX - inset - backButton.frame.width, y: inset))
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let gap: CGFloat = bounds.width < 360 ? 18 : 30
        playButton.setFrameOrigin(NSPoint(x: c.x - playButton.frame.width / 2, y: c.y - playButton.frame.height / 2))
        skipBackButton.setFrameOrigin(NSPoint(x: playButton.frame.minX - gap - skipBackButton.frame.width, y: c.y - skipBackButton.frame.height / 2))
        skipAheadButton.setFrameOrigin(NSPoint(x: playButton.frame.maxX + gap, y: c.y - skipAheadButton.frame.height / 2))
    }

    // Only the buttons are hit; drags anywhere else reach the overlay view below. A button takes
    // its click while the controls are faded out too (the pointer was already in the window when
    // it opened, or rested there): fading is drawing, and a click on a hidden play button still
    // means play, not a drag (#134).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return buttons.first { $0.frame.contains(p) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { show() }
    override func mouseMoved(with event: NSEvent) { show() }
    override func mouseExited(with event: NSEvent) { hide(after: 0) }

    private func show() {
        if !shown {
            shown = true
            fade(to: 1, duration: 0.15)
        }
        hide(after: 2.5)
    }

    private func hide(after delay: TimeInterval) {
        hideTimer?.invalidate()
        let pointerInside = { [weak self] () -> Bool in
            guard let self, let w = self.window else { return false }
            return w.frame.contains(NSEvent.mouseLocation)
        }
        let action = { [weak self] in
            guard let self, self.shown else { return }
            // Keep the controls while the pointer rests on a button.
            if pointerInside(), self.buttons.contains(where: { $0.isHovered }) { self.hide(after: 2.5); return }
            self.shown = false
            self.fade(to: 0, duration: 0.25)
        }
        if delay == 0 { action(); return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in Task { @MainActor in action() } }
    }

    private func fade(to opacity: Float, duration: TimeInterval) {
        guard let layer else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = opacity
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = opacity
        layer.add(anim, forKey: "fade")
    }
}

/// A round, borderless control: white SF Symbol, translucent disc on hover,
/// darker while pressed.
@MainActor
final class PictureInPictureButton: NSView {
    var onClick: () -> Void = {}
    var onPress: () -> Void = {}
    var symbol: String { didSet { image.image = Self.image(symbol, pointSize) } }
    private(set) var isHovered = false { didSet { updateBackground() } }
    private var isPressed = false { didSet { updateBackground() } }
    private let pointSize: CGFloat
    private let image = NSImageView()
    private var tipAnchor: ArcTooltipAnchorView?
    /// Arc-style hover tip (ArcTooltip), not AppKit's yellow one.
    var tip: String { didSet { tipAnchor?.text = tip; setAccessibilityLabel(tip) } }

    init(symbol: String, pointSize: CGFloat, diameter: CGFloat, tip: String) {
        self.symbol = symbol
        self.pointSize = pointSize
        self.tip = tip
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        image.image = Self.image(symbol, pointSize)
        image.contentTintColor = .white
        image.imageScaling = .scaleNone
        image.frame = bounds
        image.autoresizingMask = [.width, .height]
        addSubview(image)
        tipAnchor = ArcTooltipAnchorView.attach(to: self, help: tip)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func image(_ name: String, _ size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private func updateBackground() {
        let alpha: CGFloat = isPressed ? 0.32 : (isHovered ? 0.2 : 0)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true; onPress() }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}
