import AppKit

/// Arc's Picture in Picture hover controls, drawn over the video.
///
/// Invisible until the pointer enters the window, then fades in one even dark
/// layer with the controls: back-to-tab (top-left), the page's address (centred)
/// and close (top-right), play/pause in the middle between ±15 s skips, as in Arc
/// (#246), sized by Arc's size classes, without the skips in a tiny window (#262), and Arc's
/// scrubber along the bottom for a video with an end. Fades out when the pointer leaves or rests for a while, and the window
/// is the bare video again. Only the buttons and the shown scrubber take clicks; everything else passes
/// through to the overlay, which drags and resizes the window.
@MainActor
final class PictureInPictureControlsView: NSView {
    var isPlaying = false { didSet { playButton.symbol = isPlaying ? "pause.fill" : "play.fill"; playButton.tip = isPlaying ? "Pause" : "Play" } }

    var address = "" { didSet { addressLabel.stringValue = address; needsLayout = true } }

    /// Where the video is and how long it is, in seconds (0 long: a stream, no scrubber).
    func setTime(position: Double, duration: Double) {
        let had = scrubber.isHidden
        scrubber.setTime(position: position, duration: duration)
        if had != scrubber.isHidden { needsLayout = true }
    }

    private let scrubber = PictureInPictureScrubberView()
    private let scrim = CALayer()
    private let addressLabel = NSTextField(labelWithString: "")
    private static let topButtonSize: CGFloat = 26
    private let closeButton = PictureInPictureButton(symbol: "xmark", pointSize: 12, diameter: topButtonSize, tip: "Close")
    private let backButton = PictureInPictureButton(symbol: "pip.exit", pointSize: 13, diameter: topButtonSize, tip: "Back to Tab")
    // Sized in layout() from PictureInPictureLayout.centreControls.
    private let playButton = PictureInPictureButton(symbol: "play.fill", pointSize: 28, diameter: 52, tip: "Play")
    private let skipBackButton = PictureInPictureButton(symbol: "gobackward.15", pointSize: 28, diameter: 46, tip: "Skip back 15 seconds")
    private let skipAheadButton = PictureInPictureButton(symbol: "goforward.15", pointSize: 28, diameter: 46, tip: "Skip ahead 15 seconds")
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
        addSubview(scrubber)
        scrubber.onPress = { [weak self] in self?.show() }
        scrubber.onSeek = { PictureInPictureChrome.shared.actions?.seek($0) }
        scrubber.isPlaying = { PictureInPictureChrome.shared.isPlaying }
        scrubber.togglePlayback = { PictureInPictureChrome.shared.actions?.togglePlayback() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The centre cluster as laid out, for `cra://debug?pip`.
    var readout: String {
        layoutSubtreeIfNeeded()
        return "play=\(Int(playButton.frame.width)) skips=\(skipBackButton.isHidden ? 0 : 1) scrub=\(scrubber.isHidden ? 0 : 1) at=\(scrubber.percent)"
    }

    /// `cra://debug?pipSeek=<0…1>`: the scrubber pressed and let go that far along.
    func debugScrub(_ fraction: CGFloat) {
        layoutSubtreeIfNeeded()
        let track = PictureInPictureScrubber.track(in: bounds.size)
        scrubber.press(at: CGPoint(x: track.minX + track.width * fraction, y: track.midY), in: bounds.size)
        scrubber.release()
    }

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
        // The centre grows with the window as Arc's does; a window taller than 16:9 sizes it by its
        // height, so it stays clear of the top bar.
        let centre = PictureInPictureLayout.centreControls(width: min(bounds.width, bounds.height * 16 / 9))
        playButton.resize(pointSize: centre.playPointSize, diameter: centre.playDiameter)
        skipBackButton.resize(pointSize: centre.skipPointSize, diameter: centre.skipDiameter)
        skipAheadButton.resize(pointSize: centre.skipPointSize, diameter: centre.skipDiameter)
        skipBackButton.isHidden = !centre.showsSkips
        skipAheadButton.isHidden = !centre.showsSkips
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        playButton.setFrameOrigin(NSPoint(x: c.x - playButton.frame.width / 2, y: c.y - playButton.frame.height / 2))
        skipBackButton.setFrameOrigin(NSPoint(x: playButton.frame.minX - centre.gap - skipBackButton.frame.width, y: c.y - skipBackButton.frame.height / 2))
        skipAheadButton.setFrameOrigin(NSPoint(x: playButton.frame.maxX + centre.gap, y: c.y - skipAheadButton.frame.height / 2))
        // The scrubber's view is the band that takes the pointer; its capsule is drawn inside.
        let area = PictureInPictureScrubber.dragArea(in: bounds.size)
        scrubber.frame = NSRect(x: area.minX, y: bounds.height - area.maxY, width: area.width, height: area.height)
        scrubber.track = PictureInPictureScrubber.track(in: bounds.size).offsetBy(dx: -area.minX, dy: -area.minY)
    }

    // Only the buttons are hit; drags anywhere else reach the overlay view below. A button takes
    // its click while the controls are faded out too (the pointer was already in the window when
    // it opened, or rested there): fading is drawing, and a click on a hidden play button still
    // means play, not a drag (#134).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if let b = buttons.first(where: { !$0.isHidden && $0.frame.contains(p) }) { return b }
        // The scrubber only while it shows: a press on the bare video's bottom moves the window.
        return shown && !scrubber.isHidden && scrubber.frame.contains(p) ? scrubber : nil
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
            if self.scrubber.isDragging { self.hide(after: 2.5); return }
            if pointerInside(), self.buttons.contains(where: { $0.isHovered && !$0.isHidden }) { self.hide(after: 2.5); return }
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

/// Arc's scrubber: a white capsule filling over white 30 %. A press goes to that spot and a drag
/// seeks, slower the higher the pointer is (`PictureInPictureScrubber` in CraCore). Hidden for a
/// video with no end.
@MainActor
final class PictureInPictureScrubberView: NSView {
    var onSeek: (Double) -> Void = { _ in }
    var onPress: () -> Void = {}
    /// Whether the video plays now, and the way to pause or play it: a playing video holds while
    /// the scrubber is held and plays on when it is let go, as Arc's (`wasPlayingAtDragBegin`).
    var isPlaying: () -> Bool = { false }
    var togglePlayback: () -> Void = {}
    /// The capsule in this view's coordinates.
    var track: CGRect = .zero { didSet { redraw() } }
    private var position = 0.0
    private var duration = 0.0
    private var drag: PictureInPictureScrubber?
    private let rail = CALayer()
    private let fill = CALayer()

    var isDragging: Bool { drag != nil }
    /// How far the fill is, 0…100, for `cra://debug?pip`.
    var percent: Int { Int((PictureInPictureScrubber.fraction(position: position, duration: duration) * 100).rounded()) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        rail.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        fill.backgroundColor = NSColor.white.cgColor
        for l in [rail, fill] {
            l.cornerRadius = PictureInPictureScrubber.thickness / 2
            layer?.addSublayer(l)
        }
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Time")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The page's word on where the video is. A drag in progress knows better until it ends.
    func setTime(position: Double, duration: Double) {
        self.duration = duration
        isHidden = !PictureInPictureScrubber.shows(duration: duration)
        guard drag == nil else { return }
        self.position = position
        redraw()
    }

    private func redraw() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        rail.frame = track
        fill.frame = CGRect(x: track.minX, y: track.minY, width: track.width * PictureInPictureScrubber.fraction(position: position, duration: duration), height: track.height)
        CATransaction.commit()
    }

    /// A press at `point` in a window of `size` (origin bottom left): the video goes there.
    func press(at point: CGPoint, in size: CGSize) {
        guard drag == nil, let d = PictureInPictureScrubber(press: point, in: size, duration: duration, playing: isPlaying()) else { return }
        drag = d
        if d.wasPlaying { togglePlayback() }
        seek(to: d.position)
    }

    func release() {
        guard let d = drag else { return }
        drag = nil
        if d.wasPlaying { togglePlayback() }
    }

    private func seek(to seconds: Double) {
        position = seconds
        redraw()
        onSeek(seconds)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // The overlay window is as large as the video, so a point in it is a point in the window.
    override func mouseDown(with event: NSEvent) {
        guard let size = window?.frame.size else { return }
        onPress()
        press(at: event.locationInWindow, in: size)
    }
    override func mouseDragged(with event: NSEvent) {
        guard drag != nil else { return }
        onPress()
        seek(to: drag!.move(to: event.locationInWindow))
    }
    override func mouseUp(with event: NSEvent) { release() }
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
    private var pointSize: CGFloat
    private var diameter: CGFloat
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

    /// A new glyph size and disc for a round button (the centre ones grow with the window, #262).
    func resize(pointSize: CGFloat, diameter: CGFloat) {
        guard pointSize != self.pointSize || diameter != self.diameter else { return }
        self.pointSize = pointSize
        self.diameter = diameter
        image.image = Self.image(symbol, pointSize)
        if label == nil { layer?.cornerRadius = diameter / 2 }
        setFrameSize(NSSize(width: diameter, height: diameter))
    }

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
