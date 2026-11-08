import AVKit
import AppKit
import CoreImage

/// Arc's preview for a picture or video picked in Library ▸ Media (MediaPreviewWindow, Arc 1.172.1;
/// CraCore MediaPreview has the measurements): a panel over the dimmed window that grows out of the
/// picked thumbnail, the Library and the space left as they were. ✕, Esc or a click on the dimmed
/// window closes it; ‹ › and the arrow keys step through the grid; ⋯ has the file's menu and "Open
/// in Preview" hands it to the Mac's app for it.
@MainActor
final class MediaPreviewController {
    static let shared = MediaPreviewController()
    private var overlay: MediaPreviewOverlay?

    var isShown: Bool { overlay != nil }

    /// `thumbnail` is where the picked picture is drawn, in screen points.
    func show(_ files: [MediaLibrary.File], at index: Int, from thumbnail: NSRect?, over parent: NSWindow) {
        guard files.indices.contains(index) else { return }
        overlay?.close(animated: false)
        let o = MediaPreviewOverlay(parent: parent, files: files, index: index, thumbnail: thumbnail) { [weak self] in self?.overlay = nil }
        overlay = o
        o.open()
        CraLog.note("media preview opens \(files[index].name)")
    }

    func close() { overlay?.close(animated: true) }
}

private final class MediaPreviewOverlay: NSWindow {
    private weak var hostWindow: NSWindow?
    private var files: [MediaLibrary.File]
    private var index: Int
    private let thumbnail: NSRect?
    private let openedAt: Int
    private let onClose: () -> Void
    private let root = OverlayRoot()
    private let panel = MediaPreviewPanel()
    private var closing = false
    /// The preview's keys, whichever window AppKit keeps key (a child panel isn't always made key).
    private var keys: Any?

    init(parent: NSWindow, files: [MediaLibrary.File], index: Int, thumbnail: NSRect?, onClose: @escaping () -> Void) {
        hostWindow = parent
        self.files = files
        self.index = index
        self.thumbnail = thumbnail
        openedAt = index
        self.onClose = onClose
        super.init(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        root.onClickOutside = { [weak self] in self?.close(animated: true) }
        contentView = root
        root.addSubview(panel)
        panel.onClose = { [weak self] in self?.close(animated: true) }
        panel.onStep = { [weak self] in self?.step($0) }
        panel.onOpenInApp = { [weak self] in self?.openInApp() }
        panel.onMenu = { [weak self] in self?.fileMenu(at: $0) }
        layoutPanel()
        panel.show(files[index], canBack: index > 0, canForward: index < files.count - 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func layoutPanel() {
        let bounds = NSRect(origin: .zero, size: frame.size)
        root.frame = bounds
        panel.frame = MediaPreview.panel(in: bounds)
        root.panelFrame = panel.frame
    }

    func open() {
        guard let parent = hostWindow else { return }
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !self.closing, e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            return self.handle(e) ? nil : e
        }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let c = MediaPreview.curve
        let timing = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
        let dim = CABasicAnimation(keyPath: "backgroundColor")
        dim.fromValue = NSColor.black.withAlphaComponent(0).cgColor
        dim.toValue = root.layer?.backgroundColor
        dim.duration = MediaPreview.openDuration
        dim.timingFunction = timing
        root.layer?.add(dim, forKey: "dim")
        guard let layer = panel.layer else { return }
        let from = reduce ? nil : startTransform()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from == nil ? 0 : 0.6
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        if let from {
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: from)
            grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            animations.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = MediaPreview.openDuration
        group.timingFunction = timing
        layer.add(group, forKey: "open")
    }

    /// The panel scaled and moved so its picture lies on the picked thumbnail (Arc grows it from there).
    private func startTransform() -> CATransform3D? {
        guard let thumb = thumbnail, index == openedAt, let layer = panel.layer else { return nil }
        let local = NSRect(origin: NSPoint(x: thumb.minX - frame.minX, y: thumb.minY - frame.minY), size: thumb.size)
        let media = panel.mediaFrameInRoot()
        guard media.width > 0, local.width > 0 else { return nil }
        let s = local.width / media.width
        // The layer scales about its centre (anchor 0.5, 0.5).
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let pc = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        // Where the picture's centre lands after scaling about the panel's centre, then the shift onto the thumbnail.
        let scaledMedia = CGPoint(x: pc.x + (media.midX - pc.x) * s, y: pc.y + (media.midY - pc.y) * s)
        var t = CATransform3DMakeTranslation(local.midX - scaledMedia.x, local.midY - scaledMedia.y, 0)
        t = CATransform3DScale(t, s, s, 1)
        return t
    }

    func close(animated: Bool) {
        guard !closing else { return }
        closing = true
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        onClose()
        let finish = { [weak self] in
            guard let self else { return }
            self.hostWindow?.removeChildWindow(self)
            self.orderOut(nil)
            self.panel.stop()
            self.hostWindow?.makeKey()
        }
        guard animated, let layer = panel.layer else { finish(); return }
        let c = MediaPreview.curve
        CATransaction.begin()
        CATransaction.setCompletionBlock(finish)
        let back = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : startTransform()
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.toValue = NSValue(caTransform3D: back ?? CATransform3DMakeScale(0.96, 0.96, 1))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = back == nil ? 0 : 0.4
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = MediaPreview.closeDuration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, c.2, c.3)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "close")
        let undim = CABasicAnimation(keyPath: "backgroundColor")
        undim.toValue = NSColor.black.withAlphaComponent(0).cgColor
        undim.duration = MediaPreview.closeDuration
        undim.fillMode = .forwards
        undim.isRemovedOnCompletion = false
        root.layer?.add(undim, forKey: "undim")
        CATransaction.commit()
    }

    private func step(_ delta: Int) {
        guard let next = MediaPreview.step(index, by: delta, count: files.count) else { NSSound.beep(); return }
        index = next
        CraLog.note("media preview shows \(files[index].name)")
        panel.show(files[index], canBack: index > 0, canForward: index < files.count - 1)
    }

    private func openInApp() {
        let url = URL(fileURLWithPath: files[index].path)
        NSWorkspace.shared.open(url)
        close(animated: true)
    }

    /// The ⋯ menu: the file's actions, as on a download (Arc's Download Context Menu).
    private func fileMenu(at point: NSPoint) {
        let url = URL(fileURLWithPath: files[index].path)
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Open") { [weak self] in NSWorkspace.shared.open(url); self?.close(animated: true) }
        MenuItems.add(m, "Show in Finder") { [weak self] in NSWorkspace.shared.activateFileViewerSelecting([url]); self?.close(animated: true) }
        m.addItem(.separator())
        MenuItems.add(m, "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
        m.addItem(.separator())
        MenuItems.add(m, "Move to Trash") { [weak self] in
            NSWorkspace.shared.recycle([url]) { _, _ in }
            self?.close(animated: true)
        }
        m.popUp(positioning: nil, at: point, in: panel)
    }

    /// Esc closes, ← → step, Space closes a picture (as Quick Look; a video keeps it for play/pause).
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: close(animated: true)
        case 123: step(-1)
        case 124: step(1)
        case 49 where !panel.isVideo: close(animated: true)
        default: return false
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { close(animated: true) }
}

/// The dimmed window: a click outside the panel closes it.
private final class OverlayRoot: NSView {
    var panelFrame: NSRect = .zero
    var onClickOutside: () -> Void = {}
    override func mouseDown(with event: NSEvent) {
        if !panelFrame.contains(convert(event.locationInWindow, from: nil)) { onClickOutside() }
    }
}

private final class MediaPreviewPanel: NSView {
    var onClose: () -> Void = {}
    var onStep: (Int) -> Void = { _ in }
    var onOpenInApp: () -> Void = {}
    var onMenu: (NSPoint) -> Void = { _ in }
    private(set) var isVideo = false

    private let backdrop = CALayer()
    private let wash = CALayer()
    private let header = NSView()
    private let closeButton = HeaderButton(symbol: "xmark", label: "Close")
    private let backButton = HeaderButton(symbol: "chevron.left", label: "Previous")
    private let forwardButton = HeaderButton(symbol: "chevron.right", label: "Next")
    private let name = NSTextField(labelWithString: "")
    private let age = NSTextField(labelWithString: "")
    private let moreButton = HeaderButton(symbol: "ellipsis", label: "More", filled: true)
    private let openButton = HeaderButton(symbol: "arrow.up.right", label: "Open in Preview", title: "Open in Preview", filled: true)
    private let picture = NSImageView()
    private var player: AVPlayerView?
    private var mediaSize = NSSize(width: 4, height: 3)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = MediaPreview.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        backdrop.contentsGravity = .resizeAspectFill
        layer?.addSublayer(backdrop)
        wash.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        layer?.addSublayer(wash)
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(red: 0.18, green: 0.22, blue: 0.26, alpha: 0.42).cgColor
        addSubview(header)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = NSColor.white.withAlphaComponent(0.92)
        name.lineBreakMode = .byTruncatingMiddle
        age.font = .systemFont(ofSize: 13)
        age.textColor = NSColor.white.withAlphaComponent(0.55)
        for v in [closeButton, backButton, forwardButton, name, age, moreButton, openButton] as [NSView] { header.addSubview(v) }
        closeButton.action = { [weak self] _ in self?.onClose() }
        backButton.action = { [weak self] _ in self?.onStep(-1) }
        forwardButton.action = { [weak self] _ in self?.onStep(1) }
        openButton.action = { [weak self] _ in self?.onOpenInApp() }
        moreButton.action = { [weak self] b in
            guard let self else { return }
            self.onMenu(self.convert(NSPoint(x: b.frame.minX, y: b.frame.minY - 4), from: b.superview))
        }
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 4
        picture.layer?.masksToBounds = true
        addSubview(picture)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ file: MediaLibrary.File, canBack: Bool, canForward: Bool) {
        name.stringValue = file.name
        age.stringValue = MediaPreview.age(file.date, now: Date())
        backButton.isEnabled = canBack
        forwardButton.isEnabled = canForward
        let url = URL(fileURLWithPath: file.path)
        let app = NSWorkspace.shared.urlForApplication(toOpen: url).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Preview"
        openButton.setTitle("Open in \(app)")
        stop()
        let ext = url.pathExtension.lowercased()
        isVideo = ["mov", "mp4", "m4v"].contains(ext)
        if isVideo {
            let asset = AVURLAsset(url: url)
            let v = AVPlayerView()
            v.controlsStyle = .floating
            v.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            v.wantsLayer = true
            v.layer?.cornerRadius = 4
            v.layer?.masksToBounds = true
            addSubview(v)
            player = v
            picture.isHidden = true
            mediaSize = NSSize(width: 16, height: 9)
            Task { @MainActor [weak self] in
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize), let t = try? await track.load(.preferredTransform) else { return }
                let r = CGRect(origin: .zero, size: size).applying(t)
                self?.mediaSize = NSSize(width: abs(r.width), height: abs(r.height))
                self?.needsLayout = true
            }
            v.player?.play()
            MediaScanner.shared.thumbnail(file, size: 400) { [weak self] img in self?.setBackdrop(img) }.map(setBackdrop)
        } else {
            picture.isHidden = false
            let image = NSImage(contentsOf: url)
            picture.image = image
            if let rep = image?.representations.first, rep.pixelsWide > 0 {
                mediaSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            } else {
                mediaSize = image?.size ?? NSSize(width: 4, height: 3)
            }
            setBackdrop(image)
        }
        needsLayout = true
    }

    func stop() {
        player?.player?.pause()
        player?.removeFromSuperview()
        player = nil
    }

    /// The panel's backdrop: the picture itself, blurred and lightened.
    private func setBackdrop(_ image: NSImage?) {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { backdrop.contents = nil; return }
        let ci = CIImage(cgImage: cg)
        let small = ci.transformed(by: CGAffineTransform(scaleX: 256 / max(ci.extent.width, 1), y: 256 / max(ci.extent.width, 1)))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 24).cropped(to: small.extent)
        let ctx = CIContext()
        backdrop.contents = ctx.createCGImage(blurred, from: small.extent)
    }

    /// The picture's frame in the overlay's coordinates.
    func mediaFrameInRoot() -> NSRect {
        let m = MediaPreview.media(mediaSize, in: NSRect(origin: .zero, size: bounds.size))
        return m.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        wash.frame = bounds
        CATransaction.commit()
        let h = MediaPreview.headerHeight
        header.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        // Arc: ✕ 24 pt in, ‹ at 60, › at 92 (centres); the name 112 pt in; ⋯ and the button 7 pt from the right.
        closeButton.frame = NSRect(x: 24 - 15, y: 8, width: 30, height: 30)
        backButton.frame = NSRect(x: 60 - 14, y: 8, width: 28, height: 30)
        forwardButton.frame = NSRect(x: 92 - 14, y: 8, width: 28, height: 30)
        let ow = openButton.fittingWidth
        openButton.frame = NSRect(x: bounds.width - 7 - ow, y: 8, width: ow, height: 30)
        moreButton.frame = NSRect(x: openButton.frame.minX - 8 - 36, y: 8, width: 36, height: 30)
        let ageW = ceil(age.intrinsicContentSize.width)
        let nameW = min(ceil(name.attributedStringValue.size().width) + 8, max(0, moreButton.frame.minX - 16 - 112 - 8 - ageW))
        name.frame = NSRect(x: 112, y: (h - 17) / 2, width: nameW, height: 17)
        age.frame = NSRect(x: name.frame.maxX + 8, y: (h - 17) / 2, width: ageW, height: 17)
        let m = MediaPreview.media(mediaSize, in: NSRect(origin: .zero, size: bounds.size))
        picture.frame = m
        player?.frame = m
    }
}

/// A header control: a glyph (✕ ‹ › ⋯) or a filled button with a title and a trailing glyph.
private final class HeaderButton: NSView {
    var action: (HeaderButton) -> Void = { _ in }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.35 } }
    private let glyph = NSImageView()
    private let text = NSTextField(labelWithString: "")
    private let filled: Bool
    private var hovering = false { didSet { refresh() } }

    init(symbol: String, label: String, title: String? = nil, filled: Bool = false) {
        self.filled = filled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: title == nil ? 15 : 13, weight: .semibold))
        glyph.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        addSubview(glyph)
        if let title { setTitle(title) }
        text.font = .systemFont(ofSize: 13, weight: .semibold)
        text.textColor = NSColor.white.withAlphaComponent(0.9)
        addSubview(text)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title ?? label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ t: String) {
        text.stringValue = t
        setAccessibilityLabel(t)
        needsLayout = true
        superview?.superview?.needsLayout = true
    }

    var fittingWidth: CGFloat { text.stringValue.isEmpty ? 36 : ceil(text.intrinsicContentSize.width) + 12 + 6 + 14 + 10 }

    private func refresh() {
        let base: CGFloat = filled ? 0.14 : 0
        layer?.backgroundColor = NSColor.white.withAlphaComponent(base + (hovering && isEnabled ? 0.1 : 0)).cgColor
    }

    override func layout() {
        super.layout()
        let s = glyph.image?.size ?? .zero
        if text.stringValue.isEmpty {
            glyph.frame = NSRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
        } else {
            let tw = ceil(text.intrinsicContentSize.width)
            text.frame = NSRect(x: 12, y: (bounds.height - 17) / 2, width: tw, height: 17)
            glyph.frame = NSRect(x: text.frame.maxX + 6, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action(self)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
