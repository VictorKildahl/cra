import AppKit
import AudioToolbox
import CoreImage
import CraCEF
import QuartzCore
import UniformTypeIdentifiers

/// Arc's Capture (⇧⌘2, the camera in the Site Control Center), measured on Arc 1.171 (offline Arc,
/// 2x window captures and 120 fps recordings, 4 Nov 2026; numbers in docs/arc-reverse-engineering.md).
/// The page turns grey and darker in one frame; the element under the pointer stays in colour inside
/// a dark ring that springs from element to element; a click takes that element, a drag takes a
/// rectangle; a white hint at the bottom says which. Once taken, the capture stays lit and a dark
/// menu beside it copies, saves or sends it, or starts again.
///
/// Cra draws all of it over a picture of the page taken as the mode starts (Chromium's own
/// Page.captureScreenshot), in a panel over the page, so the page itself is never touched and the
/// capture is exactly what was on screen. Decisions (picker, geometry) are in CraCore's ContentCapture.
@MainActor
final class CaptureOverlay {
    enum Action: Equatable {
        case copy, save, message, newEasel, retake
        /// Arc's image editor over the capture (#851); the capture stays, edited.
        case edit
        /// The easel picked in the menu.
        case sendToEasel(UUID)

        /// New Easel or an easel's row: the capture keeps where on its page it came from.
        var goesToAnEasel: Bool {
            if case .sendToEasel = self { return true }
            return self == .newEasel
        }
    }

    /// The easels a capture can go to, the latest edited first: the menu's rows after New Easel.
    /// The app sets it at launch (the overlay knows nothing of where easels are kept).
    static var easels: () -> [CaptureMenuLayout.Destination] = { [] }

    /// Set by cra://debug?captureMenu=: a test copy runs behind other windows, where its panel
    /// can lose the keys as it opens, which would end the mode before the menu is read.
    var staysWithoutKeys = false

    private let panel: CapturePanel
    private let view: CaptureView
    private weak var parent: NSWindow?
    private var closed = false
    /// Called once, when the overlay goes away; with the action and the capture's PNG if one was chosen.
    var onFinish: ((Action?, Data?) -> Void)?

    /// `pageRect`: the page on screen; `shot`: the page's pixels, top-left first.
    init(over window: NSWindow, pageRect: NSRect, shot: CGImage, browser: CraBrowser) {
        parent = window
        panel = CapturePanel(contentRect: pageRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = CaptureView(frame: NSRect(origin: .zero, size: pageRect.size), shot: shot, browser: browser, scale: window.backingScaleFactor)
        panel.contentView = view
        view.finish = { [weak self] action, png in self?.finish(action, png) }
        panel.onResignKey = { [weak self] in
            // Another window took the keys (the sidebar, another app): the mode ends, as in Arc.
            // Not while the editor is open: its Image tool's file picker takes them (#851).
            guard let self, !self.closed, self.view.isSettled, self.view.editor == nil, !self.staysWithoutKeys else { return }
            CraLog.note("capture: another window took the keys, the mode ends")
            self.finish(nil, nil)
        }
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        view.start()
    }

    var isOpen: Bool { !closed }
    var parentWindow: NSWindow? { parent }

    func close() { finish(nil, nil) }

    /// Capture Image…: takes the image at `rect` (page points) straight away (CaptureView.lift).
    func lift(_ rect: CGRect) { view.lift(rect) }

    /// What was captured, in page points from the page's top left, and the page's size: an easel
    /// keeps them so the capture can show the live page (Easel.Capture).
    var takenRect: CGRect? { view.takenRect }
    var pageSize: CGSize { view.bounds.size }
    /// The element a click would take now, in page points (the harness reads it).
    var pickedElement: CGRect? { view.pickedElement }
    /// cra://debug?captureMenu=: `typed` goes in the menu's field; its rows, then `run` is chosen.
    func debugMenu(typed: String, run: String?) -> String { view.debugMenu(typed: typed, run: run) }
    /// The capture editor, while it is open (#851).
    var editor: (any CaptureEditing)? { view.editor }

    private func finish(_ action: Action?, _ png: Data?) {
        guard !closed else { return }
        closed = true
        view.stop()
        // The menu's field may hold the keyboard: its text editor ends with the mode.
        if panel.firstResponder !== view { panel.makeFirstResponder(view) }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        NSCursor.arrow.set()
        onFinish?(action, png)
        onFinish = nil
    }
}

final class CapturePanel: NSPanel {
    var onResignKey: (() -> Void)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // After the event that moved the keys, so a click in the menu's own window doesn't count.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isKeyWindow else { return }
            self.onResignKey?()
        }
    }
}

/// Arc's colours for Capture (ARC_Capture.bundle's asset catalog, dark appearance where it has one).
enum CaptureStyle {
    /// The ring around what is being captured (measured #161C2F).
    static let ring = NSColor(srgbRed: 22 / 255, green: 28 / 255, blue: 47 / 255, alpha: 1)
    /// Greyscale (Rec. 601 luma) under a 25 % black veil: 243 → 181, 255 → 191 (measured).
    static let dim: CGFloat = 0.75
    /// Arc's OverlayBubbleText, which reads at ~78 % on the white card (measured 93,55,169 at its darkest).
    static let bubbleText = NSColor(srgbRed: 0.204, green: 0.021, blue: 0.58, alpha: 0.78)
    static let bubbleBlue = NSColor(srgbRed: 0, green: 0.278, blue: 1, alpha: 0.5)
    static let bubblePink = NSColor(srgbRed: 1, green: 0.6, blue: 0.6, alpha: 0.5)
}

/// The capture menu's colours for the Mac's appearance: white with black text in Light mode, Arc's dark navy in Dark
/// (CraCore CaptureMenuTones, #822).
struct CaptureMenuColors {
    let fill, text, icon, divider, field, prompt, hover, hoverText: NSColor

    init(dark: Bool = SystemAppearance.shared.isDark) {
        let t = CaptureMenuTones(dark: dark)
        func color(_ i: CaptureMenuTones.Ink) -> NSColor { NSColor(srgbRed: i.rgb.r, green: i.rgb.g, blue: i.rgb.b, alpha: i.alpha) }
        (fill, text, icon, divider) = (color(t.fill), color(t.text), color(t.icon), color(t.divider))
        (field, prompt, hover, hoverText) = (color(t.field), color(t.prompt), color(t.hover), color(t.hoverText))
    }
}

// MARK: - The page, the lens and the pointer

@MainActor
final class CaptureView: NSView {
    enum Mode { case selecting, dragging(start: CGPoint), captured(CGRect) }

    var finish: ((CaptureOverlay.Action?, Data?) -> Void)?
    /// The page as shown: taken again while it scrolls under the mode (#195).
    private var shot: CGImage
    private weak var browser: CraBrowser?
    private let scale: CGFloat
    private var mode: Mode = .selecting
    /// The area the capture holds (page points), once taken.
    private(set) var takenRect: CGRect?

    private let colourLayer = CALayer()
    private let greyFull = CALayer()
    private let greyHoled = CALayer()
    private let holeMask = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let ringShadow = CAShapeLayer()
    private let ringShadowMask = CAShapeLayer()
    /// Capture Image…: the image, moved off its place on the page to the middle (`lift`).
    private let liftLayer = CALayer()
    private var lifted = false
    private let bubble = CaptureBubble()
    private var actionsMenu: CaptureMenu?
    /// The capture as the menu's rows take it: what was taken, or that with what the editor put on it (#851).
    private var capturedImage: CGImage?
    private var capturedPNG: Data?
    /// The edited capture, shown where the capture stays lit.
    private let editedLayer = CALayer()
    private(set) var editor: (any CaptureEditing)?

    // The lens: where it is, where it is going, and how much of it shows.
    private var lens: CGRect?
    private var lensTarget: CGRect?
    private var lensVelocity = [CGFloat](repeating: 0, count: 4)
    private var lensAlpha: CGFloat = 0
    private var lensAlphaTarget: CGFloat = 0
    private var link: CADisplayLink?
    private var lastStep: CFTimeInterval = 0

    // The picker: one question at a time, the latest point waiting.
    private var element: CGRect?
    private var probing = false
    private var pendingProbe: CGPoint?
    private var pointer: CGPoint?

    // Scrolling under the mode (#195): the page's devicePixelRatio (its zoom times the display's
    // scale), and one new picture at a time, the latest wish waiting.
    private var pageRatio: CGFloat?
    private var refreshing = false
    private var refreshAgain = false
    private var settleRefresh: DispatchWorkItem?

    /// While a choice made in the menu is being carried out, losing the keys isn't a cancel.
    private(set) var isSettled = true

    init(frame: NSRect, shot: CGImage, browser: CraBrowser, scale: CGFloat) {
        self.shot = shot
        self.browser = browser
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
        let root = layer!
        root.backgroundColor = NSColor.black.cgColor
        let grey = Self.dimmed(shot)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [colourLayer, greyFull, greyHoled] {
            l.frame = bounds
            l.contentsGravity = .resize
            l.contentsScale = scale
            root.addSublayer(l)
        }
        colourLayer.contents = shot
        greyFull.contents = grey
        greyHoled.contents = grey
        holeMask.fillRule = .evenOdd
        holeMask.frame = bounds
        greyHoled.mask = holeMask
        greyFull.opacity = 1
        ringShadow.fillColor = NSColor.black.cgColor
        ringShadow.fillRule = .evenOdd
        ringShadow.shadowColor = NSColor.black.cgColor
        ringShadow.shadowOpacity = 0.32
        ringShadow.shadowRadius = 10
        ringShadow.shadowOffset = CGSize(width: 0, height: 3)
        ringShadow.opacity = 0
        // The ring's shadow falls outside it only, never on the lit page inside.
        ringShadowMask.fillRule = .evenOdd
        ringShadowMask.frame = bounds
        ringShadow.mask = ringShadowMask
        ring.fillColor = CaptureStyle.ring.cgColor
        ring.fillRule = .evenOdd
        ring.opacity = 0
        liftLayer.isHidden = true
        liftLayer.contentsGravity = .resize
        liftLayer.contentsScale = scale
        liftLayer.cornerRadius = ContentCapture.lensInnerRadius
        liftLayer.masksToBounds = true
        root.addSublayer(liftLayer)
        editedLayer.isHidden = true
        editedLayer.contentsGravity = .resize
        editedLayer.contentsScale = scale
        editedLayer.cornerRadius = ContentCapture.lensInnerRadius
        editedLayer.masksToBounds = true
        root.addSublayer(editedLayer)
        root.addSublayer(ringShadow)
        root.addSublayer(ring)
        CATransaction.commit()
        addSubview(bubble)
        layoutBubble()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func start() {
        deeper = NSEvent.modifierFlags.contains(.option)
        browser?.evaluate(inIsolatedWorld: PageScript.world, params: #"{"expression":"devicePixelRatio","returnByValue":true}"#) { [weak self] result, _ in
            let ratio = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { ($0["result"] as? [String: Any])?["value"] as? Double }
            DispatchQueue.main.async { if let ratio, ratio > 0 { self?.pageRatio = ratio } }
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited], owner: self))
        bubble.appear()
        if let p = window?.mouseLocationOutsideOfEventStream, bounds.contains(convert(p, from: nil)) {
            pointerMoved(to: convert(p, from: nil))
        }
        updateCursor()
    }

    func stop() {
        link?.invalidate()
        link = nil
        settleRefresh?.cancel()
        settleRefresh = nil
    }

    /// Greyscale by Rec. 601 luma in the image's own (gamma) values, times `CaptureStyle.dim`, which
    /// is what Arc shows (243,241,235 → 181; 212,73,76 → 86; 79,155,143 → 98).
    private static func dimmed(_ image: CGImage) -> CGImage? {
        let k = CaptureStyle.dim
        let filter = CIFilter(name: "CIColorMatrix")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        let row = CIVector(x: 0.299 * k, y: 0.587 * k, z: 0.114 * k, w: 0)
        filter.setValue(row, forKey: "inputRVector")
        filter.setValue(row, forKey: "inputGVector")
        filter.setValue(row, forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard let out = filter.outputImage else { return nil }
        // No working colour space: the matrix applies to the stored values, as Arc's does.
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        return context.createCGImage(out, from: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                                     format: .RGBA8, colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    // MARK: Pointer

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let actionsMenu, actionsMenu.frame.contains(p) { NSCursor.arrow.set(); return }
        if case .selecting = mode {
            deeper = event.modifierFlags.contains(.option)
            pointerMoved(to: p)
        }
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        if case .selecting = mode {
            pointer = nil
            stack = nil
            setElement(nil)
        }
    }

    private func pointerMoved(to p: CGPoint) {
        pointer = p
        probe(p)
    }

    private func updateCursor() {
        switch mode {
        case .selecting: (element == nil ? CaptureCursors.cross : CaptureCursors.camera).set()
        case .dragging: CaptureCursors.cross.set()
        case .captured: NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if case .captured = mode {
            if let actionsMenu, actionsMenu.frame.contains(p) { return }
            // A press beside the capture starts over, from this press.
            dropMenu()
            editedLayer.isHidden = true
            if lifted {
                lifted = false
                liftLayer.isHidden = true
                snapLens(to: nil)
            }
            mode = .selecting
            bubble.show(true)
        }
        mode = .dragging(start: p)
        pressedOnElement = element
    }

    private var pressedOnElement: CGRect?

    override func mouseDragged(with event: NSEvent) {
        guard case .dragging(let start) = mode else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard ContentCapture.isDrag(from: start, to: p) || pressedOnElement == nil else { return }
        pressedOnElement = nil
        let r = ContentCapture.selection(from: start, to: p, in: bounds)
        element = nil
        bubble.setCanClick(false)
        snapLens(to: r.isEmpty ? nil : r)
        CaptureCursors.cross.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard case .dragging(let start) = mode else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let clicked = pressedOnElement, !ContentCapture.isDrag(from: start, to: p) {
            capture(clicked, lens: ContentCapture.clearArea(element: clicked))
            return
        }
        let r = ContentCapture.selection(from: start, to: p, in: bounds)
        if ContentCapture.isCapturable(r) {
            capture(r, lens: r)
        } else {
            mode = .selecting
            snapLens(to: nil)
            pointerMoved(to: p)
            updateCursor()
        }
    }

    // MARK: Scrolling

    /// Arc scrolls the page under the mode: the wheel goes to the page, as a wheel over it would,
    /// and the picture is taken again as it moves (#195). Not while dragging or once captured.
    override func scrollWheel(with event: NSEvent) {
        guard case .selecting = mode, let browser, browser.isCreated, !browser.isClosed else { return }
        let p = convert(event.locationInWindow, from: nil)
        // Points to CSS pixels: the page's zoom is its devicePixelRatio over the display's scale.
        let css = scale / (pageRatio ?? scale)
        // A wheel's lines are Chrome's 40 px each; a trackpad's deltas are points.
        let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 40
        let dx = -event.scrollingDeltaX * line * css, dy = -event.scrollingDeltaY * line * css
        guard dx != 0 || dy != 0 else { return }
        let params: [String: Any] = ["type": "mouseWheel", "x": p.x * css, "y": p.y * css, "deltaX": dx, "deltaY": dy, "pointerType": "mouse"]
        guard let json = (try? JSONSerialization.data(withJSONObject: params)).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        browser.sendDevToolsMethod("Input.dispatchMouseEvent", params: json) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshShot() }
        }
        // Smooth scrolling and momentum keep the page moving after the last event.
        settleRefresh?.cancel()
        let settle = DispatchWorkItem { [weak self] in self?.refreshShot() }
        settleRefresh = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: settle)
    }

    /// A new picture of the page for the grey page, the lens and the capture.
    private func refreshShot() {
        guard let browser, browser.isCreated, !browser.isClosed, case .selecting = mode else { return }
        if refreshing { refreshAgain = true; return }
        refreshing = true
        browser.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","captureBeyondViewport":false,"optimizeForSpeed":true}"#) { [weak self] shot, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                if case .selecting = self.mode, let image = MainWindowController.screenshotImage(shot) { self.show(image) }
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refreshShot()
                }
            }
        }
    }

    private func show(_ image: CGImage) {
        shot = image
        let grey = Self.dimmed(image)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colourLayer.contents = image
        greyFull.contents = grey
        greyHoled.contents = grey
        CATransaction.commit()
        // What is under the pointer moved with the page.
        if let pointer { probe(pointer) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if editor != nil { return }
        if let actionsMenu, actionsMenu.handleKey(event) { return }
        if event.keyCode == 53 { finish?(nil, nil); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { if editor == nil { finish?(nil, nil) } }

    /// Any other shortcut (a new tab, another space) ends the mode before the menu bar runs it; the
    /// capture shortcut is left to the menu bar, which closes the mode itself.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The editor's sheet keeps ⌘Z, ⌘C, ⌘V and the rest for what is drawn on the capture.
        if editor != nil { return super.performKeyEquivalent(with: event) }
        // With a capture taken, ⌘C and ⌘S copy and save it.
        if case .captured = mode, let menu = actionsMenu,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "c": menu.run(.copy); return true
            case "s": menu.run(.save); return true
            default: break
            }
        }
        // The "Send To…" field holding the keyboard keeps ⌘A ⌘V ⌘X ⌘Z for its text (the Edit menu's).
        if actionsMenu?.hasKeyboard == true, event.modifierFlags.intersection([.command, .control, .option]) == .command,
           CaptureMenuLayout.fieldKeeps(commandKey: event.charactersIgnoringModifiers ?? "") {
            return false
        }
        if event.modifierFlags.contains(.command), KeyBindingRegistry.shared.action(for: event)?.id != "capturePage" {
            finish?(nil, nil)
        }
        return false
    }

    // MARK: The element under the pointer

    private func probe(_ p: CGPoint) {
        guard let browser, browser.isCreated, !browser.isClosed else { return }
        if probing { pendingProbe = p; return }
        probing = true
        let script = ContentCapture.pickerScript(x: p.x * scale, y: p.y * scale)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing = false
                let stack = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { ($0["result"] as? [String: Any])?["value"] as? [String: Any] }
                    .flatMap(ContentCapture.pickerStack(from:))
                if let next = self.pendingProbe {
                    self.pendingProbe = nil
                    self.probe(next)
                }
                // Only while the pointer is still choosing, and only if it is still over this answer's point.
                guard case .selecting = self.mode, self.pointer != nil else { return }
                self.stack = stack
                self.choose()
            }
        }
    }

    /// What the page last said is under the pointer, so ⌥ can choose again without asking it.
    private var stack: ContentCapture.PickerStack?
    /// ⌥ held, as the last event said: the element right under the pointer instead of Arc's choice (#451).
    private var deeper = false
    var pickedElement: CGRect? { element }

    private func choose() {
        let rect = stack.flatMap { ContentCapture.elementRect(ContentCapture.choose(in: $0, deeper: deeper), scale: scale, pageBounds: bounds) }
        if let rect, let ptr = pointer, !rect.insetBy(dx: -2, dy: -2).contains(ptr) { return }
        setElement(rect)
    }

    override func flagsChanged(with event: NSEvent) {
        let held = event.modifierFlags.contains(.option)
        if held != deeper {
            deeper = held
            if case .selecting = mode, pointer != nil { choose() }
        }
        super.flagsChanged(with: event)
    }

    private func setElement(_ rect: CGRect?) {
        guard rect != element else { return }
        element = rect
        bubble.setCanClick(rect != nil)
        if let rect {
            springLens(to: ContentCapture.clearArea(element: rect))
        } else {
            fadeLens()
        }
        updateCursor()
    }

    // MARK: Capture

    /// `rect` is what goes in the image; `lens` what stays lit (an element's 2 pt more).
    private func capture(_ rect: CGRect, lens clear: CGRect) {
        mode = .captured(rect)
        takenRect = rect
        element = nil
        pressedOnElement = nil
        snapLens(to: clear)
        let px = ContentCapture.pixelRect(for: rect, pageSize: bounds.size, imageSize: CGSize(width: shot.width, height: shot.height))
        guard let cropped = shot.cropping(to: px), let png = Self.png(cropped) else { finish?(nil, nil); return }
        took(cropped, png: png)
        CaptureSound.play()
        bubble.show(false)
        showMenu(png: png)
        NSCursor.arrow.set()
    }

    /// Capture Image… (a page's context menu, Arc's): `rect`, an image on the page, is taken at once
    /// and springs from its place to the middle of the grey page, the menu beside it
    /// (ContentCapture.liftedLayout). Its place on the page stays grey.
    func lift(_ rect: CGRect) {
        let px = ContentCapture.pixelRect(for: rect, pageSize: bounds.size, imageSize: CGSize(width: shot.width, height: shot.height))
        guard let cropped = shot.cropping(to: px), let png = Self.png(cropped) else { finish?(nil, nil); return }
        took(cropped, png: png)
        let menu = makeMenu(png: png)
        let layout = ContentCapture.liftedLayout(image: rect.size, menu: menu.intrinsicContentSize, in: bounds)
        mode = .captured(layout.image)
        takenRect = rect
        element = nil
        pressedOnElement = nil
        lifted = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liftLayer.contents = cropped
        liftLayer.isHidden = false
        CATransaction.commit()
        snapLens(to: rect)
        lensTarget = layout.image
        run()
        CaptureSound.play()
        bubble.show(false)
        dropMenu()
        menu.frame = layout.menu
        addSubview(menu)
        menu.appear()
        actionsMenu = menu
        menu.focus()
        NSCursor.arrow.set()
    }

    /// A new capture: nothing edited on it yet.
    private func took(_ image: CGImage, png: Data) {
        capturedImage = image
        capturedPNG = png
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        editedLayer.isHidden = true
        editedLayer.contents = nil
        CATransaction.commit()
    }

    // MARK: Edit (#851)

    /// Arc's Edit row: the capture opens in Arc's image editor over the page; a click on the dark page around it
    /// brings the capture back, with what was drawn, and the menu stays to copy, save or send it.
    func openEditor() {
        guard editor == nil, case .captured = mode, let image = capturedImage, let e = CaptureEditors.make(bounds, image) else { return }
        e.autoresizingMask = [.width, .height]
        e.onDone = { [weak self] edited in self?.edited(edited) }
        addSubview(e)
        editor = e
        e.layoutSubtreeIfNeeded()
        e.focus()
    }

    private func edited(_ image: CGImage) {
        editor = nil
        guard image !== capturedImage, let png = Self.png(image) else { actionsMenu?.focus(); return }
        capturedImage = image
        capturedPNG = png
        if case .captured(let rect) = mode {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if lifted {
                liftLayer.contents = image
            } else {
                editedLayer.frame = rect
                editedLayer.contents = image
                editedLayer.isHidden = false
            }
            CATransaction.commit()
        }
        actionsMenu?.focus()
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private func makeMenu(png: Data) -> CaptureMenu {
        // Only the easels that fit the page inside its margins (a Peek or a Little Window is short).
        let room = bounds.height - 2 * ContentCapture.menuMargin
        let menu = CaptureMenu(easels: CaptureOverlay.easels(), maxHeight: room) { [weak self] action in
            guard let self else { return }
            if action == .edit { self.openEditor(); return }
            self.isSettled = false
            if action == .retake {
                self.finish?(.retake, nil)
            } else {
                self.finish?(action, self.capturedPNG ?? png)
            }
        }
        menu.onCancel = { [weak self] in self?.finish?(nil, nil) }
        return menu
    }

    func debugMenu(typed: String, run: String?) -> String {
        guard let menu = actionsMenu else { return "no menu" }
        menu.debugType(typed)
        let line = "typed=\(typed) keyboard=\(menu.hasKeyboard ? "field" : "elsewhere") rows=\(menu.debugRows)"
        if let run { DispatchQueue.main.async { if !menu.debugRun(run) { CraLog.note("capture menu: no row \(run)") } } }
        return line
    }

    private func showMenu(png: Data) {
        dropMenu()
        let m = makeMenu(png: png)
        let lensFrame = ContentCapture.lensFrame(around: lens ?? .zero)
        m.frame = ContentCapture.menuFrame(size: m.intrinsicContentSize, besideLens: lensFrame, in: bounds)
        addSubview(m)
        m.appear()
        actionsMenu = m
        m.focus()
    }

    private func dropMenu() {
        guard let menu = actionsMenu else { return }
        // The keys go back to the page's picture before the field that held them leaves.
        if menu.hasKeyboard { window?.makeFirstResponder(self) }
        menu.removeFromSuperview()
        actionsMenu = nil
    }

    // MARK: Lens drawing and motion

    /// Arc's FocusRectAnimator: a spring on the whole rectangle (measured 120 fps: ~0.15 s to arrive,
    /// 0.4 % overshoot), i.e. stiffness ≈ 2000, damping ≈ 78 for unit mass.
    private static let stiffness: CGFloat = 2000
    private static let damping: CGFloat = 78
    /// The lens fades in and out (Arc's lensOpacity).
    private static let fadeDuration: CGFloat = 0.12

    private func springLens(to rect: CGRect) {
        if lens == nil || lensAlpha < 0.05 {
            lens = rect
            lensVelocity = [0, 0, 0, 0]
        }
        lensTarget = rect
        lensAlphaTarget = 1
        run()
    }

    private func fadeLens() {
        lensAlphaTarget = 0
        run()
    }

    /// Straight to `rect` (a drag), no spring.
    private func snapLens(to rect: CGRect?) {
        if let rect {
            lens = rect
            lensTarget = rect
            lensVelocity = [0, 0, 0, 0]
            lensAlpha = 1
            lensAlphaTarget = 1
        } else {
            lensAlphaTarget = 0
            lensAlpha = 0
        }
        draw()
        run()
    }

    private func run() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
        lastStep = CACurrentMediaTime()
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastStep, 1.0 / 30)
        var dt = elapsed
        lastStep = now
        var moving = false
        if var r = lens, let t = lensTarget {
            var v = lensVelocity
            var cur = [r.minX, r.minY, r.width, r.height]
            let goal = [t.minX, t.minY, t.width, t.height]
            while dt > 0 {
                let h = min(dt, 1.0 / 480)
                for i in 0..<4 {
                    let a = -Self.stiffness * (cur[i] - goal[i]) - Self.damping * v[i]
                    v[i] += a * h
                    cur[i] += v[i] * h
                }
                dt -= h
            }
            r = CGRect(x: cur[0], y: cur[1], width: cur[2], height: cur[3])
            if zip(cur, goal).allSatisfy({ abs($0 - $1) < 0.05 }) && v.allSatisfy({ abs($0) < 0.5 }) {
                r = t
                v = [0, 0, 0, 0]
            } else {
                moving = true
            }
            lens = r
            lensVelocity = v
        }
        if lensAlpha != lensAlphaTarget {
            let d = CGFloat(elapsed) / Self.fadeDuration
            lensAlpha = lensAlphaTarget > lensAlpha ? min(lensAlphaTarget, lensAlpha + d) : max(lensAlphaTarget, lensAlpha - d)
            moving = true
        }
        draw()
        if !moving {
            l.invalidate()
            link = nil
            if lensAlpha == 0 { lens = nil; lensTarget = nil }
        }
    }

    private func draw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let full = CGPath(rect: bounds, transform: nil)
        if let r = lens, lensAlpha > 0 {
            let inner = ContentCapture.lensInnerRadius
            let outer = inner + ContentCapture.lensRing
            let clear = CGPath(roundedRect: r, cornerWidth: min(inner, r.width / 2), cornerHeight: min(inner, r.height / 2), transform: nil)
            let o = ContentCapture.lensFrame(around: r)
            let outerPath = CGPath(roundedRect: o, cornerWidth: min(outer, o.width / 2), cornerHeight: min(outer, o.height / 2), transform: nil)
            let hole = CGMutablePath()
            hole.addPath(full)
            hole.addPath(clear)
            holeMask.path = hole
            let ringPath = CGMutablePath()
            ringPath.addPath(outerPath)
            ringPath.addPath(clear)
            ring.path = ringPath
            ringShadow.path = outerPath
            ringShadow.shadowPath = outerPath
            let outside = CGMutablePath()
            outside.addPath(full)
            outside.addPath(outerPath)
            ringShadowMask.path = outside
            ring.opacity = Float(lensAlpha)
            ringShadow.opacity = Float(lensAlpha)
            greyFull.opacity = Float(1 - lensAlpha)
            // A lifted image covers the hole exactly: the page under it stays out of sight.
            if lifted { liftLayer.frame = r }
        } else {
            holeMask.path = full
            ring.opacity = 0
            ringShadow.opacity = 0
            greyFull.opacity = 1
        }
        CATransaction.commit()
    }

    private func layoutBubble() {
        let size = CaptureBubble.size
        bubble.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: bounds.height - CaptureBubble.bottomInset - size.height,
                              width: size.width, height: size.height)
    }
}

// MARK: - The hint at the bottom

/// Arc's ContentCaptureOverlayBubble: a white 354 × 65 pt card 36.5 pt above the page's bottom,
/// centred, 17 pt corners, a hairline from pink to blue, 14 pt semibold purple text, in a soft
/// pink and blue glow. "Click or drag…" while there is an element to click, "Drag…" otherwise.
/// It fades in over ~0.16 s; the dimming itself is instant.
final class CaptureBubble: NSView {
    static let size = CGSize(width: 354, height: 65)
    static let bottomInset: CGFloat = 36.5
    static let cornerRadius: CGFloat = 17
    static let clickText = "Click or drag to capture a portion of this page"
    static let dragText = "Drag to capture a portion of this page"

    private let glowPink = CAGradientLayer()
    private let glowBlue = CAGradientLayer()
    private let card = CALayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let label = NSTextField(labelWithString: CaptureBubble.dragText)
    private var canClick = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        // Arc's glow darkens the dimmed page with a tint rather than lighting it (measured beside the
        // card: 163 grey → 155,147,148 on the left, 140,143,156 on the right, gone ~90 pt out).
        let pink = NSColor(srgbRed: 95 / 255, green: 45 / 255, blue: 50 / 255, alpha: 0.3)
        let blue = NSColor(srgbRed: 20 / 255, green: 35 / 255, blue: 120 / 255, alpha: 0.34)
        for (g, c) in [(glowPink, pink), (glowBlue, blue)] {
            g.type = .radial
            g.colors = [c.cgColor, c.withAlphaComponent(0).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(g)
        }
        card.backgroundColor = NSColor.white.cgColor
        card.cornerRadius = Self.cornerRadius
        card.cornerCurve = .continuous
        layer?.addSublayer(card)
        rim.colors = [CaptureStyle.bubblePink.withAlphaComponent(0.35).cgColor, CaptureStyle.bubbleBlue.withAlphaComponent(0.35).cgColor]
        rim.startPoint = CGPoint(x: 0, y: 0.5)
        rim.endPoint = CGPoint(x: 1, y: 0.5)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 1
        rim.mask = rimMask
        layer?.addSublayer(rim)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = CaptureStyle.bubbleText
        label.alignment = .center
        addSubview(label)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.frame = bounds
        rim.frame = bounds
        rimMask.frame = bounds
        rimMask.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: Self.cornerRadius - 0.5, cornerHeight: Self.cornerRadius - 0.5, transform: nil)
        // The glow: pink low on the left, blue on the right, spilling well past the card.
        glowPink.frame = CGRect(x: -130, y: -70, width: 330, height: 205)
        glowBlue.frame = CGRect(x: bounds.width - 200, y: -80, width: 330, height: 225)
        CATransaction.commit()
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: ((bounds.height - label.frame.height) / 2).rounded(), width: bounds.width, height: label.frame.height)
    }

    func appear() {
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.16
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func show(_ visible: Bool) {
        alphaValue = visible ? 1 : 0
    }

    func setCanClick(_ can: Bool) {
        guard can != canClick else { return }
        canClick = can
        label.stringValue = can ? Self.clickText : Self.dragText
    }
}

// MARK: - The menu after a capture

/// Arc's CapturedImageActionsView (Arc 1.173.1, 17 Nov 2026): 273 pt wide, 10 pt corners, its colours from the Mac's
/// appearance, whatever the space (CaptureMenuColors, #822): fill (18,15,46) in Dark mode, white in Light; a "Send To…" field on top that takes the keyboard and
/// narrows the rows as you type; 40 pt rows with a 13 pt symbol centred 25 pt in at white 30 % and
/// 14 pt medium text from 41 pt at white 90 %; sections apart by 9 pt with a hairline 10 pt in from
/// both sides. The last section is where the capture can go: New Easel, then each easel by name
/// (CraCore CaptureMenuLayout). Edit opens Arc's image editor (#851); Arc's Save to Library row Cra doesn't have.
final class CaptureMenu: NSView, NSTextFieldDelegate {
    static let cornerRadius: CGFloat = 10

    private let easels: [CaptureMenuLayout.Destination]
    /// The page's height inside its margins: the menu lists only the easels that fit.
    private let maxHeight: CGFloat
    private var sections: [[CaptureMenuLayout.Row]]
    private var rows: [CaptureMenuLayout.Row] = []
    private var rowViews: [CaptureMenuRow] = []
    private var lines: [NSView] = []
    private let fieldBox = NSView()
    private let field = NSTextField()
    private var selected: Int? { didSet { for (i, r) in rowViews.enumerated() { r.highlighted = i == selected } } }
    private let choose: (CaptureOverlay.Action) -> Void
    private let colors = CaptureMenuColors()
    /// Escape in the field.
    var onCancel: () -> Void = {}

    init(easels: [CaptureMenuLayout.Destination], maxHeight: CGFloat = .infinity, choose: @escaping (CaptureOverlay.Action) -> Void) {
        self.easels = easels
        self.maxHeight = maxHeight
        self.choose = choose
        sections = CaptureMenuLayout.sections(easels: easels, maxHeight: maxHeight)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = colors.fill.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            s.shadowBlurRadius = 12
            s.shadowOffset = NSSize(width: 0, height: -4)
            return s
        }()
        let m = CaptureMenuLayout.self
        fieldBox.wantsLayer = true
        fieldBox.layer?.backgroundColor = colors.field.cgColor
        fieldBox.layer?.cornerRadius = 7
        fieldBox.layer?.cornerCurve = .continuous
        fieldBox.frame = NSRect(x: m.fieldInset, y: m.fieldTop, width: m.width - 2 * m.fieldInset, height: m.fieldHeight)
        addSubview(fieldBox)
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = colors.text
        field.placeholderAttributedString = NSAttributedString(string: "Send To…", attributes: [.font: font, .foregroundColor: colors.prompt])
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = self
        field.setAccessibilityLabel("Send To")
        let fh = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 8, y: ((m.fieldHeight - fh) / 2).rounded(), width: fieldBox.frame.width - 16, height: fh)
        fieldBox.addSubview(field)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// For scenarios (#822): the fill and the rows' text colour the menu opens with.
    var debugColors: (fill: NSColor, ink: NSColor) {
        (layer?.backgroundColor.flatMap(NSColor.init(cgColor:)) ?? .clear, field.textColor ?? .clear)
    }

    override var isFlipped: Bool { true }

    private static func symbol(_ item: CaptureMenuLayout.Item) -> String {
        switch item {
        case .copy: "doc.on.doc.fill"
        case .save: "square.and.arrow.down.fill"
        case .message: "message.fill"
        case .edit: "pencil.tip.crop.circle"
        case .retake: "arrow.counterclockwise"
        case .newEasel: "plus"
        case .easel: "scribble"
        }
    }

    private static func action(_ item: CaptureMenuLayout.Item) -> CaptureOverlay.Action {
        switch item {
        case .copy: .copy
        case .save: .save
        case .message: .message
        case .edit: .edit
        case .retake: .retake
        case .newEasel: .newEasel
        case .easel(let id): .sendToEasel(id)
        }
    }

    /// The rows for what is typed, laid out under the field.
    private func rebuild() {
        rowViews.forEach { $0.removeFromSuperview() }
        lines.forEach { $0.removeFromSuperview() }
        rowViews = []
        lines = []
        rows = []
        let m = CaptureMenuLayout.self
        var y = m.header
        for (si, section) in sections.enumerated() {
            if si > 0 {
                let line = NSView(frame: NSRect(x: 10, y: y + 4.25, width: m.width - 20, height: 0.5))
                line.wantsLayer = true
                line.layer?.backgroundColor = colors.divider.cgColor
                addSubview(line)
                lines.append(line)
                y += m.sectionGap
            }
            for row in section {
                let index = rowViews.count
                let v = CaptureMenuRow(title: row.title, symbol: Self.symbol(row.item), colors: colors) { [weak self] in self?.choose(Self.action(row.item)) }
                v.onHover = { [weak self] inside in
                    if inside { self?.selected = index } else if self?.selected == index { self?.selected = nil }
                }
                v.frame = NSRect(x: 0, y: y, width: m.width, height: m.rowHeight)
                addSubview(v)
                rowViews.append(v)
                rows.append(row)
                y += m.rowHeight
            }
        }
        selected = nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CaptureMenuLayout.width, height: CaptureMenuLayout.height(sections))
    }

    func appear() {
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.12
            animator().alphaValue = 1
        }
    }

    /// The field takes the keyboard, as Arc's does when the menu shows: on the next turn of the
    /// run loop, once the menu is in its window for good. A menu dropped before then (a retake,
    /// the mode ending) never starts a text editor, which a window being closed would hold on to.
    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible, self.superview != nil else { return }
            window.makeFirstResponder(self.field)
        }
    }
    var hasKeyboard: Bool { field.currentEditor() != nil }

    func run(_ action: CaptureOverlay.Action) { choose(action) }

    // MARK: Typing

    func controlTextDidChange(_ obj: Notification) { narrow() }

    private func narrow() {
        sections = CaptureMenuLayout.sections(easels: easels, filter: field.stringValue, maxHeight: maxHeight)
        rebuild()
        // The menu keeps its top (its view counts down from there) and ends under its last row.
        frame.size.height = intrinsicContentSize.height
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): return runSelected()
        case #selector(NSResponder.cancelOperation(_:)): onCancel(); return true
        default: return false
        }
    }

    private func move(_ by: Int) {
        guard !rowViews.isEmpty else { return }
        if let i = selected { selected = min(max(i + by, 0), rowViews.count - 1) } else { selected = by > 0 ? 0 : rowViews.count - 1 }
    }

    /// Return: the picked row, or the first one left once something is typed.
    private func runSelected() -> Bool {
        if let i = selected { rowViews[i].run(); return true }
        guard let row = CaptureMenuLayout.defaultRow(sections, filter: field.stringValue) else { return false }
        choose(Self.action(row.item))
        return true
    }

    /// ↑ ↓ pick a row, Return runs it (while the picture, not the field, has the keyboard).
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: move(1); return true
        case 126: move(-1); return true
        case 36, 76: return runSelected()
        default: return false
        }
    }

    // MARK: Test hooks

    var debugRows: String {
        sections.map { $0.map(\.title).joined(separator: "|") }.joined(separator: "|—|")
    }

    func debugType(_ text: String) {
        guard field.stringValue != text else { return }
        field.stringValue = text
        narrow()
    }

    func debugRun(_ title: String) -> Bool {
        guard let i = rows.firstIndex(where: { $0.title == title }) else { return false }
        rowViews[i].run()
        return true
    }
}

final class CaptureMenuRow: NSView {
    private let fill = CALayer()
    private let icon = NSImageView()
    private let label: NSTextField
    private let action: () -> Void
    var onHover: ((Bool) -> Void)?
    var highlighted = false { didSet { paint() } }

    private let colors: CaptureMenuColors

    init(title: String, symbol: String, colors: CaptureMenuColors, action: @escaping () -> Void) {
        self.action = action
        self.colors = colors
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        fill.cornerRadius = 6
        fill.cornerCurve = .continuous
        layer?.addSublayer(fill)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.imageScaling = .scaleNone
        label.font = .systemFont(ofSize: 14, weight: .medium)
        addSubview(icon)
        addSubview(label)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        label.lineBreakMode = .byTruncatingTail
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func layout() {
        super.layout()
        fill.frame = bounds.insetBy(dx: 5, dy: 2)
        icon.frame = NSRect(x: 25 - 10, y: (bounds.height - 20) / 2, width: 20, height: 20)
        label.sizeToFit()
        // A long easel name ends in an ellipsis inside the menu.
        label.frame.size.width = min(label.frame.width, bounds.width - 41 - 14)
        label.frame.origin = NSPoint(x: 41, y: ((bounds.height - label.frame.height) / 2).rounded())
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { run() }
    }

    override func accessibilityPerformPress() -> Bool { run(); return true }

    func run() { action() }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.backgroundColor = highlighted ? colors.hover.cgColor : nil
        CATransaction.commit()
        label.textColor = highlighted ? colors.hoverText : colors.text
        icon.contentTintColor = highlighted ? colors.hoverText : colors.icon
    }
}

// MARK: - Pointers and sound

/// Arc's two capture pointers, drawn the same way: a dark camera with a white outline over an
/// element that a click would take, and a crosshair with that camera at its top right elsewhere.
@MainActor
enum CaptureCursors {
    static let camera: NSCursor = {
        let size = NSSize(width: 24, height: 19)
        let image = NSImage(size: size, flipped: false) { r in
            drawCamera(in: r.insetBy(dx: 1, dy: 1))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    static let cross: NSCursor = {
        let size = NSSize(width: 34, height: 32)
        let image = NSImage(size: size, flipped: false) { _ in
            // The crosshair: 16 pt arms, 1.5 pt dark lines on a light halo, centred 9 pt from the
            // bottom-left; the camera above and right of it.
            let c = NSPoint(x: 9, y: 9)
            for (color, width) in [(NSColor.white.withAlphaComponent(0.8), 3.5), (NSColor(white: 0.17, alpha: 1), 1.5)] {
                color.setStroke()
                let p = NSBezierPath()
                p.lineWidth = width
                p.move(to: NSPoint(x: c.x - 8, y: c.y)); p.line(to: NSPoint(x: c.x + 8, y: c.y))
                p.move(to: NSPoint(x: c.x, y: c.y - 8)); p.line(to: NSPoint(x: c.x, y: c.y + 8))
                p.stroke()
            }
            drawCamera(in: NSRect(x: 12, y: 14, width: 21, height: 16))
            return true
        }
        // Hot spots count from the top-left.
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: size.height - 9))
    }()

    /// A camera body with a lens ring and a dot, dark with a white outline, in `r` (y up).
    private static func drawCamera(in r: NSRect) {
        let body = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.78)
        let hump = NSRect(x: r.midX - r.width * 0.2, y: body.maxY - 2, width: r.width * 0.4, height: r.height * 0.22 + 2)
        let shape = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        shape.append(NSBezierPath(roundedRect: hump, xRadius: 1.5, yRadius: 1.5))
        NSColor.white.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        NSColor(srgbRed: 0.13, green: 0.16, blue: 0.19, alpha: 1).setFill()
        shape.fill()
        let d = body.height * 0.5
        let lens = NSBezierPath(ovalIn: NSRect(x: body.midX - d / 2, y: body.midY - d / 2, width: d, height: d))
        NSColor.white.setStroke()
        lens.lineWidth = 1.4
        lens.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: body.maxX - 4.5, y: body.maxY - 4.5, width: 2, height: 2)).fill()
    }
}

/// macOS's own screenshot sound, when a capture is taken (Arc plays its capture.wav there). A
/// system sound plays in the sound server, so the main thread never waits for an output device.
@MainActor
enum CaptureSound {
    private static let id: SystemSoundID? = {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif")
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr ? id : nil
    }()

    /// Settings ▸ Advanced "Play Cra sound effects" (Arc's "Play Arc sound effects").
    static var enabled = true

    static func play() {
        if enabled, let id { AudioServicesPlaySystemSound(id) }
    }
}
