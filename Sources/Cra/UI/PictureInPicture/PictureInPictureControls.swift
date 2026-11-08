import AppKit

/// Arc's Picture in Picture hover controls, drawn over the video.
///
/// Invisible until the pointer enters the window, then fades in one even dark
/// layer with the controls: back-to-tab (top-left), the page's address (centred)
/// and close (top-right), play/pause in the middle between ±15 s skips, as in Arc
/// (#246). Fades out when the pointer leaves or rests for a while, and the window
/// is the bare video again. Only the buttons take clicks; everything else passes
/// through to the overlay, which drags and resizes the window.
@MainActor
final class PictureInPictureControlsView: NSView {
    var isPlaying = false { didSet { playButton.symbol = isPlaying ? "pause.fill" : "play.fill"; playButton.tip = isPlaying ? "Pause" : "Play" } }

    var address = "" { didSet { addressLabel.stringValue = address; needsLayout = true } }

    private let scrim = CALayer()
    private let addressLabel = NSTextField(labelWithString: "")
    private static let topButtonSize: CGFloat = 26
    private let closeButton = PictureInPictureButton(symbol: "xmark", pointSize: 12, diameter: topButtonSize, tip: "Close")
    private let backButton = PictureInPictureButton(symbol: "pip.exit", pointSize: 13, diameter: topButtonSize, tip: "Back to Tab")
    private let playButton = PictureInPictureButton(symbol: "play.fill", pointSize: 22, diameter: 48, tip: "Play")
    private let skipBackButton = PictureInPictureButton(symbol: "gobackward.15", pointSize: 17, diameter: 38, tip: "Skip back 15 seconds")
    private let skipAheadButton = PictureInPictureButton(symbol: "goforward.15", pointSize: 17, diameter: 38, tip: "Skip ahead 15 seconds")
    private var buttons: [PictureInPictureButton] { [backButton, closeButton, playButton, skipBackButton, skipAheadButton] }
    private var hideTimer: Timer?
    private var shown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
        // Arc dims the whole frame evenly, from the top bar to the bottom edge; Cra's gradient
        // darkened the top and bottom and left the middle almost clear (#246).
        scrim.backgroundColor = NSColor.black.withAlphaComponent(PictureInPictureLayout.scrimAlpha).cgColor
        layer?.addSublayer(scrim)
        addressLabel.font = .systemFont(ofSize: PictureInPictureLayout.addressFontSize, weight: .medium)
        addressLabel.textColor = .white
        addressLabel.alignment = .center
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.maximumNumberOfLines = 1
        addSubview(addressLabel)
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
        // Back to Tab shows its words from 400 pt wide, as in Arc.
        backButton.label = PictureInPictureLayout.labelsBackToTab(width: bounds.width) ? "Back to Tab" : nil
        let bar = PictureInPictureLayout.topBar(width: bounds.width, buttonSize: Self.topButtonSize, backWidth: backButton.fittingWidth,
                                                addressWidth: addressLabel.stringValue.isEmpty ? 0 : PictureInPictureButton.textWidth(addressLabel))
        backButton.frame = bar.back
        closeButton.frame = bar.close
        addressLabel.isHidden = bar.address == nil
        if let a = bar.address {
            let h = ceil(addressLabel.intrinsicContentSize.height)
            addressLabel.frame = NSRect(x: a.minX, y: a.midY - h / 2, width: a.width, height: h)
        }
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
            fade(to: 1, duration: PictureInPictureLayout.fadeDuration)
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
            self.fade(to: 0, duration: PictureInPictureLayout.fadeDuration)
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
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)   // Arc: .easeInOut(duration: 0.2)
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
    private let diameter: CGFloat
    private let image = NSImageView()
    private let text = NSTextField(labelWithString: "")
    /// Words after the glyph: the button becomes a pill (Arc's Back to Tab on a wide window,
    /// 12 pt medium, 6 pt continuous corners, 10 pt padding).
    var label: String? {
        didSet {
            guard label != oldValue else { return }
            text.stringValue = label ?? ""
            text.isHidden = label == nil
            layer?.cornerRadius = label == nil ? diameter / 2 : 6
            needsLayout = true
        }
    }
    /// The width the button wants: its disc, or the glyph and its words.
    var fittingWidth: CGFloat {
        guard label != nil else { return diameter }
        return (10 + (image.image?.size.width ?? 14) + 5 + Self.textWidth(text) + 10).rounded(.up)
    }
    private var tipAnchor: ArcTooltipAnchorView?
    /// Arc-style hover tip (ArcTooltip), not AppKit's yellow one.
    var tip: String { didSet { tipAnchor?.text = tip; setAccessibilityLabel(tip) } }

    init(symbol: String, pointSize: CGFloat, diameter: CGFloat, tip: String) {
        self.symbol = symbol
        self.pointSize = pointSize
        self.diameter = diameter
        self.tip = tip
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        image.image = Self.image(symbol, pointSize)
        image.contentTintColor = .white
        image.imageScaling = .scaleNone
        image.frame = bounds
        addSubview(image)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .white
        text.isHidden = true
        addSubview(text)
        layer?.cornerCurve = .continuous
        tipAnchor = ArcTooltipAnchorView.attach(to: self, help: tip)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard label != nil else { image.frame = bounds; return }
        let g = image.image?.size.width ?? 14
        image.frame = NSRect(x: 10, y: 0, width: g, height: bounds.height)
        let h = ceil(text.intrinsicContentSize.height)
        text.frame = NSRect(x: 10 + g + 5, y: (bounds.height - h) / 2, width: Self.textWidth(text), height: h)
    }

    /// What a one-line label needs to show all of its text: its cell's size, which adds the cell's
    /// and the line fragment's padding to the string (4 pt a side). The intrinsic width came out
    /// 4 pt short, and the address and "Back to Tab" were cut.
    static func textWidth(_ field: NSTextField) -> CGFloat {
        ceil(field.cell?.cellSize.width ?? field.intrinsicContentSize.width)
    }

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
