import AppKit
import ObjectiveC

/// Experimental: Chromium's page view lives in the pane card instead of its own child window,
/// the way Arc and Dia host pages. One window and one Core Animation tree, so the page moves,
/// resizes and animates with the card, and clicks and keys reach it without making another
/// window key.
///
/// CEF 156 only makes Chrome-style browsers (extensions, Chrome's DevTools) inside its own
/// window, so that window stays: empty, click-through, never key, laid over the card as
/// before so Chromium's menus, popups and layout still have the right screen position. Its
/// page view (WebContentsViewCocoa) moves into the card's web area.
///
/// On by default. Off with `defaults write dk.kildahl.cra embedPages -bool NO` or
/// CRA_EMBED_PAGES=0 (pages then stay in their own child windows, as before 0.1.17).
enum EmbeddedPages {
    static let isEnabled: Bool = {
        if let env = ProcessInfo.processInfo.environment["CRA_EMBED_PAGES"] { return env != "0" }
        return UserDefaults.standard.object(forKey: "embedPages") as? Bool ?? true
    }()

    /// Chrome windows whose page moved out: they must never become key or main, or keys
    /// would go to a window with nothing in it (Chromium activates its window on focus).
    private static let hosts = NSHashTable<NSWindow>.weakObjects()
    private static var patched = false

    static func markHost(_ window: NSWindow) {
        patch(window)
        hosts.add(window)
        // Its views moved out and it is clear and borderless, so it shows nothing. It keeps
        // alpha 1: Chrome pops page context menus up from it, and an alpha 0 window gets none.
        window.ignoresMouseEvents = true
        // Left out of screen capture: a screenshot app's "window under the pointer" skipped it
        // then, and takes the main window, whose card draws the page. Captured, this clear window
        // over the card came out blank white (#346). Its popups are windows of their own.
        if window.sharingType != .none { window.sharingType = .none }
    }

    /// The page went back into its window (DevTools docked in it).
    static func unmarkHost(_ window: NSWindow) {
        guard hosts.contains(window) else { return }
        hosts.remove(window)
        window.ignoresMouseEvents = false
        window.sharingType = .readOnly
    }

    static func isHost(_ window: NSWindow?) -> Bool { window.map { hosts.contains($0) } ?? false }

    /// What moves, by Chrome window, wherever the views are now (any window's card, or none
    /// while the tab is hidden), so a tab moving to another Cra window still finds its page.
    /// Chromium draws the page with the window's compositor, whose layers live in
    /// ViewsCompositorSuperview; WebContentsViewCocoa on top of it only takes input. Between them
    /// Cra's ChromeBarClicks takes what lands on a bar Chromium draws around the page. All three
    /// move, in that order, the compositor first and the page's input view last.
    private static let pages = NSMapTable<NSWindow, NSArray>.weakToStrongObjects()

    static func pageViews(of window: NSWindow) -> [NSView]? {
        if let views = pages.object(forKey: window) as? [NSView] { return views }
        guard let cv = window.contentView, let page = webContentsView(in: cv),
              let compositor = find("ViewsCompositorSuperview", in: cv) else { return nil }
        let views = [compositor, ChromeBarClicks(host: window, compositor: compositor), page]
        pages.setObject(views as NSArray, forKey: window)
        watch(page, compositor: compositor, host: window)
        return views
    }

    /// Lays page views out in `bounds` of their superview: the compositor fills it, and the input
    /// view keeps the place Chromium gave it there (below the debugger infobar, #241). Every frame
    /// Cra gives a page view goes through here, so any other change of the input view's frame is
    /// Chromium laying it out. Other views (none embedded) just fill `bounds`.
    static func place(_ views: [NSView], in bounds: NSRect) {
        placing += 1
        defer { placing -= 1 }
        for v in views {
            let flipped = v.superview?.isFlipped ?? false
            let frame = watcher(of: v).map { $0.insets.frame(in: bounds, flipped: flipped) } ?? bounds
            if v.frame != frame { v.frame = frame }
        }
    }

    /// Chromium's insets for a page's input view, for `cra://debug` and the log.
    static func chromiumInsets(of view: NSView) -> PageViewInsets? { watcher(of: view)?.insets }

    nonisolated(unsafe) private static var watcherKey: UInt8 = 0
    private static var placing = 0

    private static func watcher(of view: NSView) -> PageFrameWatcher? {
        objc_getAssociatedObject(view, &watcherKey) as? PageFrameWatcher
    }

    /// The input view still has Chromium's frame here, in its Chrome window: start from that.
    private static func watch(_ page: NSView, compositor: NSView, host: NSWindow) {
        guard watcher(of: page) == nil else { return }
        let watcher = PageFrameWatcher(host: host, compositor: compositor)
        objc_setAssociatedObject(page, &watcherKey, watcher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        page.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(watcher, selector: #selector(PageFrameWatcher.frameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: page)
        chromiumMoved(page, watcher)
    }

    /// Chromium set the input view's frame (`WebContentsNSViewBridge::SetBounds`, as its layout
    /// shows or hides a bar above the page): keep its insets, and in a card put the view where
    /// they say against the compositor, which may not be the Chrome window's size.
    fileprivate static func chromiumMoved(_ page: NSView, _ watcher: PageFrameWatcher) {
        guard placing == 0, let host = watcher.host else { return }
        let client = host.contentRect(forFrameRect: host.frame).size
        guard let insets = PageViewInsets(chromiumFrame: page.frame, superviewFlipped: page.superview?.isFlipped ?? false,
                                          clientSize: client) else { return }
        if insets != watcher.insets {
            CraLog.note("page view: Chromium insets top=\(Int(insets.top)) left=\(Int(insets.left)) bottom=\(Int(insets.bottom)) right=\(Int(insets.right))")
            watcher.insets = insets
        }
        if let compositor = watcher.compositor, let area = page.superview, compositor.superview === area, area !== host.contentView {
            place([page], in: compositor.frame)
        }
    }

    static func webContentsView(in root: NSView) -> NSView? { find("WebContentsViewCocoa", in: root) }
    static func renderView(in root: NSView) -> NSView? { find("RenderWidgetHostViewCocoa", in: root) }

    private static func find(_ className: String, in root: NSView) -> NSView? {
        if NSStringFromClass(type(of: root)) == className { return root }
        for v in root.subviews { if let found = find(className, in: v) { return found } }
        return nil
    }

    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool

    private static func patch(_ window: NSWindow) {
        guard !patched else { return }
        patched = true
        let cls: AnyClass = type(of: window)
        for name in ["canBecomeKeyWindow", "canBecomeMainWindow"] {
            let sel = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(cls, sel) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
            let block: @convention(block) (AnyObject) -> Bool = { obj in
                if let w = obj as? NSWindow, MainActor.assumeIsolated({ hosts.contains(w) }) { return false }
                return original(obj, sel)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }
}

/// An embedded page's input view's watch on its own frame (EmbeddedPages.place). Owned by the
/// view, so it and its observation end with the page.
private final class PageFrameWatcher: NSObject {
    weak var host: NSWindow?
    weak var compositor: NSView?
    var insets = PageViewInsets.zero

    init(host: NSWindow, compositor: NSView) {
        self.host = host
        self.compositor = compositor
    }

    @objc func frameChanged(_ note: Notification) {
        guard let page = note.object as? NSView else { return }
        MainActor.assumeIsolated { EmbeddedPages.chromiumMoved(page, self) }
    }
}

/// The clicks on a bar Chromium's views draw around the page, like the debugger infobar's Cancel
/// and ✕ (#241). The bar's views stay in the Chrome window, which ignores the mouse, so this view
/// fills the compositor's area under the page's input view and hands what reaches it (the bar's
/// strip) to the Chrome window at the same place in its client area.
final class ChromeBarClicks: NSView {
    private weak var host: NSWindow?
    private weak var compositor: NSView?

    init(host: NSWindow, compositor: NSView) {
        self.host = host
        self.compositor = compositor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    /// Back in its own window (DevTools docked) the Chrome window takes its clicks itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let host, window !== host else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { forward(event) }
    override func mouseDragged(with event: NSEvent) { forward(event) }
    override func mouseUp(with event: NSEvent) { forward(event) }
    override func rightMouseDown(with event: NSEvent) { forward(event) }
    override func rightMouseUp(with event: NSEvent) { forward(event) }

    private func forward(_ event: NSEvent) {
        guard let host, let compositor, let content = host.contentView else { return }
        // The compositor draws the Chrome window's client area from its top left.
        let p = compositor.convert(event.locationInWindow, from: nil)
        let fromTop = compositor.isFlipped ? p.y : compositor.bounds.height - p.y
        let inHost = content.convert(NSPoint(x: p.x, y: content.isFlipped ? fromTop : content.bounds.height - fromTop), to: nil)
        guard let e = NSEvent.mouseEvent(with: event.type, location: inHost, modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                         windowNumber: host.windowNumber, context: nil, eventNumber: event.eventNumber,
                                         clickCount: event.clickCount, pressure: event.pressure) else { return }
        host.sendEvent(e)
    }
}
