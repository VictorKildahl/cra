import AppKit
import CraCEF

/// Arc's BrowserExtensionWindow: an extension's popup in a small titled window under the
/// toolbar (close button only, transparent title bar) that can be dragged away for the
/// current opening. Every new popup starts at its own button.
///
/// Cra keeps Chrome's own popup (its page stays a real extension popup: activeTab, the
/// tab it fills into) and puts a frame window around it. Chrome's bubble becomes the
/// frame's child, so it moves with it. The frame never becomes key: Chrome closes a popup
/// as soon as it loses focus, and a click on the title bar would otherwise take it.
@MainActor
final class ExtensionPopupWindow: NSWindow {
    /// Chrome's bubble draws a transparent margin around the page.
    static let bubbleInset: CGFloat = 7
    static let titleBarHeight: CGFloat = 28
    private static var current: ExtensionPopupWindow?

    private weak var bubble: NSWindow?
    /// The top-right point (screen) the popup hangs from: right edge of its button, under the bar.
    private var anchor = NSPoint.zero
    /// Where the user dragged the frame, from hanging right under the anchor.
    private var offset = NSPoint.zero
    /// The frame's top-left when a title-bar drag began.
    private var dragStart = NSPoint.zero
    private var observers: [NSObjectProtocol] = []
    private var placing = false
    /// A title-bar drag is under way (willMove is only posted for those, not when the main
    /// window carries this child along).
    private var dragging = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        // The frame is never key, so AppKit would draw all three buttons inactive (grey).
        // Arc shows a live red close button next to two disabled ones: draw those in place.
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(kind), let superview = button.superview else { continue }
            let light = TrafficLight(close: kind == .closeButton) { [weak self] in self?.performClose(nil) }
            light.frame = button.frame
            light.autoresizingMask = button.autoresizingMask
            superview.addSubview(light)
            button.isHidden = true
        }
    }

    /// Wraps Chrome's popup `bubble`; `anchor` is the top-right point (screen) it hangs from
    /// (its right edge stays there as Chrome resizes the page).
    static func present(_ bubble: NSWindow, anchor: ExtensionPopupAnchor) {
        current?.dismiss(closingBubble: false)
        let w = ExtensionPopupWindow()
        w.bubble = bubble
        w.anchor = anchor.point
        w.appearance = bubble.parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        w.backgroundColor = .windowBackgroundColor
        current = w

        // Above the page (and the main window), below the popup.
        let host = anchor.owner ?? bubble.parent?.parent ?? bubble.parent
        bubble.parent?.removeChildWindow(bubble)
        bubble.hasShadow = false
        w.layout()
        host?.addChildWindow(w, ordered: .above)
        w.orderFront(nil)
        w.addChildWindow(bubble, ordered: .above)

        // Do not let Chrome's re-anchoring or a child-window move fight the browser's new
        // geometry. A fresh invocation will resolve the button in its new position.
        if let owner = anchor.owner {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                w.observers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak w] _ in
                    MainActor.assumeIsolated { w?.dismiss(closingBubble: true) }
                })
            }
        }

        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            w.observers.append(NotificationCenter.default.addObserver(forName: name, object: bubble, queue: .main) { [weak w] _ in
                MainActor.assumeIsolated { w?.layout() }
            })
        }
        w.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: bubble, queue: .main) { [weak w] _ in
            MainActor.assumeIsolated { w?.dismiss(closingBubble: false) }
        })
        // Chrome closes its popup when the popup loses focus, but only once it had focus: shown
        // while the page's own window wasn't key (the button is in Cra's sidebar, or Cra was in
        // the background) it never closed. Give it focus, and close it when another Cra window
        // takes focus or Cra goes to the background, as a focused popup does.
        bubble.makeKey()
        let shownAt = Date()
        w.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak w] note in
            MainActor.assumeIsolated {
                // The click that opened the popup can still be making its window key.
                guard let w, let bubble = w.bubble, let key = note.object as? NSWindow, key !== bubble, key.parent !== bubble,
                      Date().timeIntervalSince(shownAt) > 0.3 else { return }
                w.dismiss(closingBubble: true)
            }
        })
        w.observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak w] _ in
            MainActor.assumeIsolated { w?.dismiss(closingBubble: true) }
        })
        w.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willMoveNotification, object: w, queue: .main) { [weak w] _ in
            MainActor.assumeIsolated {
                guard let w else { return }
                w.dragging = true
                w.dragStart = NSPoint(x: w.frame.minX, y: w.frame.maxY)
            }
        })
        w.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak w] _ in
            MainActor.assumeIsolated { w?.userMoved() }
        })
    }

    /// Sizes the frame to the popup page and puts the bubble in it (Chrome re-anchors the
    /// bubble to its hidden toolbar whenever the page resizes).
    private func layout() {
        guard let bubble, !placing else { return }
        // While the title bar is dragged AppKit carries the bubble along; afterwards the
        // frame stays where it was dropped.
        if dragging {
            if NSEvent.pressedMouseButtons != 0 { return }
            dragging = false
        }
        placing = true
        defer { placing = false }
        let inset = Self.bubbleInset
        let size = NSSize(width: bubble.frame.width - 2 * inset, height: bubble.frame.height - 2 * inset + Self.titleBarHeight)
        // The button's display owns placement, not the hidden Chrome toolbar's display.
        let screen = NSScreen.screens.first { NSPointInRect(anchor, $0.frame) } ?? bubble.screen ?? NSScreen.main
        let frame = ExtensionPopupGeometry.frame(size: size, anchor: anchor, offset: offset, visibleFrame: screen?.visibleFrame)
        if self.frame != frame { setFrame(frame, display: true) }
        let origin = NSPoint(x: frame.minX - inset, y: frame.minY - inset)
        if bubble.frame.origin != origin { bubble.setFrameOrigin(origin) }
    }

    private func userMoved() {
        guard dragging, !placing, bubble != nil else { return }
        let moved = NSPoint(x: frame.minX, y: frame.maxY)
        // A click on the title bar that barely moved it is not a new place.
        guard hypot(moved.x - dragStart.x, moved.y - dragStart.y) > 4 else { return }
        offset = NSPoint(x: moved.x - (anchor.x - frame.width), y: moved.y - anchor.y)
    }

    override func performClose(_ sender: Any?) { dismiss(closingBubble: true) }
    override func close() { dismiss(closingBubble: true) }

    private func dismiss(closingBubble: Bool) {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        if let bubble {
            removeChildWindow(bubble)
            if closingBubble { bubble.close() }
        }
        bubble = nil
        parent?.removeChildWindow(self)
        orderOut(nil)
        if Self.current === self { Self.current = nil }
    }
}

/// A title-bar button as AppKit draws it in an active window: red close (× on hover) or a
/// disabled grey circle.
private final class TrafficLight: NSView {
    private let isClose: Bool
    private let action: () -> Void
    private var hovered = false { didSet { needsDisplay = true } }

    init(close: Bool, action: @escaping () -> Void) {
        isClose = close
        self.action = action
        super.init(frame: .zero)
        if close { addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d = min(bounds.width, bounds.height) - 2
        let circle = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let path = NSBezierPath(ovalIn: circle)
        if isClose {
            NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1).setFill()
            path.fill()
            NSColor(srgbRed: 0.886, green: 0.267, blue: 0.239, alpha: 1).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            if hovered {
                let x = NSBezierPath()
                let r = d * 0.2
                x.move(to: NSPoint(x: circle.midX - r, y: circle.midY - r)); x.line(to: NSPoint(x: circle.midX + r, y: circle.midY + r))
                x.move(to: NSPoint(x: circle.midX - r, y: circle.midY + r)); x.line(to: NSPoint(x: circle.midX + r, y: circle.midY - r))
                x.lineWidth = 1.2
                x.lineCapStyle = .round
                NSColor(srgbRed: 0.3, green: 0, blue: 0, alpha: 0.8).setStroke()
                x.stroke()
            }
        } else {
            (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.13)).setFill()
            path.fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isClose, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }
}

/// An extension's popup page when there is no page for Chrome's real popup to attach to
/// (no tab open, or no DevTools pipe): the same frame as ExtensionPopupWindow around a
/// Cra browser on the popup URL, sized the way Chrome sizes popups (the page's own size,
/// 25×25 to 800×600, following it as it changes) and closed when it loses focus.
@MainActor
final class ExtensionPageWindow: NSWindow, NSWindowDelegate, @preconcurrency CraBrowserDelegate {
    private static var current: ExtensionPageWindow?
    nonisolated static let minSize = NSSize(width: 25, height: 25)
    nonisolated static let maxSize = NSSize(width: 800, height: 600)

    private unowned let app: AppDelegate
    private var browser: CraBrowser?
    /// The frame's top-right (screen): the page grows to the left, away from its button.
    private var topRight: NSPoint
    private var pageSize: NSSize?
    private var measureTimer: Timer?
    private var closing = false
    private var ownerObservers: [NSObjectProtocol] = []

    /// The page's natural size: its max-content width, then its height at that width.
    private static let measureScript = """
        (() => { const d = document.documentElement, b = document.body; if (!b) return null;
          const old = d.style.width; d.style.width = 'max-content';
          const w = Math.ceil(d.getBoundingClientRect().width); d.style.width = old;
          const h = Math.ceil(Math.max(b.getBoundingClientRect().bottom + parseFloat(getComputedStyle(b).marginBottom || '0'),
                                       b.scrollHeight));
          return [w, h]; })()
        """

    static func open(url: String, anchor: ExtensionPopupAnchor, app: AppDelegate) {
        current?.close()
        let w = ExtensionPageWindow(url: url, anchor: anchor, app: app)
        current = w
    }

    private init(url: String, anchor: ExtensionPopupAnchor, app: AppDelegate) {
        self.app = app
        let start = NSSize(width: 360, height: 240)
        topRight = anchor.point
        super.init(contentRect: NSRect(origin: .zero, size: start), styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        standardWindowButton(.miniaturizeButton)?.isEnabled = false
        standardWindowButton(.zoomButton)?.isEnabled = false
        delegate = self
        alphaValue = 0   // shown once the page has a size
        setFrame(frame(for: start), display: false)

        let b = CraBrowser(frame: pageRect, url: url, delegate: self)
        browser = b
        let v = b.containerView
        v.frame = pageRect
        v.autoresizingMask = [.width, .height]
        contentView?.addSubview(v)
        if let host = b.hostWindow { attach(host) }
        makeKeyAndOrderFront(nil)
        // Show it even if the page never reports a size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.alphaValue = 1 }
        measureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measure() }
        }
        if let owner = anchor.owner {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                ownerObservers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.close() }
                })
            }
        }
    }

    /// The area under the title bar, in window coordinates.
    private var pageRect: NSRect {
        NSRect(x: 0, y: 0, width: frame.width, height: max(0, frame.height - ExtensionPopupWindow.titleBarHeight))
    }

    private func frame(for page: NSSize) -> NSRect {
        let size = NSSize(width: page.width, height: page.height + ExtensionPopupWindow.titleBarHeight)
        let screen = NSScreen.screens.first { NSPointInRect(topRight, $0.frame) } ?? screen ?? NSScreen.main
        return ExtensionPopupGeometry.frame(size: size, anchor: topRight, visibleFrame: screen?.visibleFrame)
    }

    private func measure() {
        guard let b = browser, !closing else { return }
        let params = String(decoding: (try? JSONSerialization.data(withJSONObject: ["expression": Self.measureScript, "returnByValue": true])) ?? Data(), as: UTF8.self)
        b.sendDevToolsMethod("Runtime.evaluate", params: params) { [weak self] result, _ in
            guard let result, let o = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                  let value = (o["result"] as? [String: Any])?["value"] as? [Double], value.count == 2 else { return }
            let size = NSSize(width: min(max(value[0], Self.minSize.width), Self.maxSize.width),
                              height: min(max(value[1], Self.minSize.height), Self.maxSize.height))
            DispatchQueue.main.async { self?.apply(size) }
        }
    }

    private func apply(_ size: NSSize) {
        guard !closing else { return }
        if let old = pageSize, abs(old.width - size.width) < 1, abs(old.height - size.height) < 1 { return }
        pageSize = size
        setFrame(frame(for: size), display: true)
        positionHost()
        alphaValue = 1
    }

    private func attach(_ host: NSWindow) {
        guard host.parent !== self else { return }
        // As MainWindowController does for tabs: borderless (a titled window keeps a title
        // bar strip above the page), the bottom corners following the frame's.
        host.styleMask.remove([.titled, .resizable])
        host.styleMask.insert(.fullSizeContentView)
        ChromiumWindowCorners.setSquare(true, for: host)
        ChromiumChildHover.setDocked(true, for: host)
        host.titlebarAppearsTransparent = true
        host.titleVisibility = .hidden
        host.isMovable = false
        host.hasShadow = false
        host.isOpaque = false
        host.backgroundColor = .clear
        if let cv = host.contentView {
            cv.isHidden = false
            cv.wantsLayer = true
            cv.layer?.cornerRadius = 12
            cv.layer?.cornerCurve = .continuous
            cv.layer?.maskedCorners = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cv.layer?.masksToBounds = true
        }
        addChildWindow(host, ordered: .above)
        positionHost()
        host.orderFront(nil)
        host.makeKey()
        browser?.setFocused(true)
    }

    private func positionHost() {
        guard let host = browser?.hostWindow, host.parent === self else { return }
        let onScreen = convertToScreen(pageRect)
        if host.frame != onScreen { host.setFrame(onScreen, display: true) }
        // Chrome leaves its content view where the title bar used to end (22 pt down).
        let full = NSRect(origin: .zero, size: onScreen.size)
        if let cv = host.contentView, cv.frame != full { cv.frame = full }
    }

    // MARK: Window

    func windowDidMove(_ notification: Notification) {
        topRight = NSPoint(x: frame.maxX, y: frame.maxY)
    }

    /// Like a popup: clicking anywhere else closes it (the page's own window is a child,
    /// so focus moving into it is not "elsewhere").
    func windowDidResignKey(_ notification: Notification) { closeIfFocusLeft() }

    private func closeIfFocusLeft() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closing else { return }
            let key = NSApp.keyWindow
            if key === self || (key != nil && key === self.browser?.hostWindow) { return }
            self.close()
        }
    }

    override func close() {
        guard !closing else { return }
        closing = true
        measureTimer?.invalidate()
        for observer in ownerObservers { NotificationCenter.default.removeObserver(observer) }
        ownerObservers = []
        if let host = browser?.hostWindow { removeChildWindow(host); host.orderOut(nil) }
        browser?.close()
        browser = nil
        super.close()
        if Self.current === self { Self.current = nil }
    }

    // MARK: CraBrowserDelegate

    func browser(_ browser: CraBrowser, didChangeTitle title: String) {}
    func browser(_ browser: CraBrowser, didChangeURL url: String) {}
    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {}
    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) {}
    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) { measure() }
    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {}
    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {}
    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) {}
    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {}
    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {
        app.useNormalWindow()
        app.store.createTab(url: url, select: !background)
    }
    /// Links the popup opens (Chrome opens them as tabs): a Cra tab.
    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? {
        app.useNormalWindow()
        app.store.createTab(url: url, select: !background)
        app.main.showWindow(nil)
        return nil
    }
    func devToolsHostView(for browser: CraBrowser) -> NSView? { nil }
    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {}
    func browserDidCloseDevTools(_ browser: CraBrowser) {}
    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) { attach(window) }
    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {}
    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {}
    func browser(_ browser: CraBrowser, handleKeyEvent event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return true }
        return app.handleReservedKey(event)
    }
    func browser(_ browser: CraBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool { app.handleUnhandledKey(event) }
    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) { app.main.browserManager(download: download) }
    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void) { completion(false) }
    func browserDidReceiveFocus(_ browser: CraBrowser) {}
    func browserDidClose(_ browser: CraBrowser) {
        // window.close() from the popup page.
        browser.containerView.removeFromSuperview()
        if !closing { close() }
    }
}
