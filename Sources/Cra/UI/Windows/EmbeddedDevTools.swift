import AppKit
import CraCEF

/// A page's DevTools on the Chromium engine, laid out as Chrome lays them out in its own window: the frontend fills
/// the page's area, docked on the side it picks, and the page lies over the room it leaves (DevToolsPlaceholder),
/// so the frontend draws its own splitter, close button and dock menu (as on CEF, where the frontend docked over
/// the area too, under the page's own window).
///
/// The page is a view in its card, and a window over the card would cover it, so the frontend comes into the card
/// too, as a view under the page: one window, as in Chrome. Its views come out of the window the bridge keeps for
/// it (CraBrowser.devToolsWindow, the DevTools window while undocked) and go back into it to undock.
@MainActor
enum EmbeddedDevTools {
    /// Holds a frontend's views in a card, under the page.
    final class Holder: NSView {
        /// The window the views came from.
        weak var home: NSWindow?
        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            for v in subviews where v.frame != bounds { v.frame = bounds }
        }
    }

    private static let holders = NSMapTable<NSWindow, Holder>.weakToStrongObjects()

    /// Whether `browser`'s DevTools go into its card: the engine's pages (the CEF bridge's are windows of their own).
    static func applies(to browser: CraBrowser?) -> Bool {
        guard let browser else { return false }
        return browser.hostWindow == nil && !(browser is WebKitBrowser)
    }

    /// The frontend of DevTools window `w`, in `area` right under `page` (else under all of the area's views).
    @discardableResult
    static func embed(_ w: NSWindow, in area: NSView, below page: NSView? = nil) -> Holder? {
        guard let cv = w.contentView else { return nil }
        let holder = holders.object(forKey: w) ?? Holder()
        holder.home = w
        holders.setObject(holder, forKey: w)
        holder.wantsLayer = true
        if !cv.subviews.isEmpty {
            for v in cv.subviews {
                holder.addSubview(v)
                v.frame = holder.bounds
                v.autoresizingMask = [.width, .height]
            }
        }
        let anchor = page?.superview === area ? page : area.subviews.first { $0 !== holder }
        let subviews = area.subviews
        if holder.superview !== area || anchor.map({ a in
            (subviews.firstIndex(of: holder) ?? 0) > (subviews.firstIndex(of: a) ?? 0)
        }) ?? false {
            area.addSubview(holder, positioned: .below, relativeTo: anchor)
        }
        holder.isHidden = false
        // Nothing of the window shows while its views are in the card.
        if w.parent != nil { w.parent?.removeChildWindow(w) }
        if w.isVisible { w.orderOut(nil) }
        return holder
    }

    /// Out of the card it was in: the frontend's views back in their window (to undock, or for a tab no card shows).
    static func restore(_ w: NSWindow) {
        guard let holder = holders.object(forKey: w), let cv = w.contentView else { return }
        holder.removeFromSuperview()
        for v in holder.subviews {
            cv.addSubview(v)
            v.frame = cv.bounds
            v.autoresizingMask = [.width, .height]
        }
    }

    /// Out of the card while its tab isn't shown there; the views stay in the holder.
    static func park(_ w: NSWindow) {
        holders.object(forKey: w)?.removeFromSuperview()
    }

    static func holder(of w: NSWindow?) -> Holder? { w.flatMap { holders.object(forKey: $0) } }

    /// The holder in `area`, if a frontend is in it.
    static func holder(in area: NSView) -> Holder? { area.subviews.lazy.compactMap { $0 as? Holder }.first }

    /// The keys to the frontend of DevTools window `w`, as Chrome gives them to DevTools it shows
    /// (DevToolsFrontendCalls): docked in a card of `window`, it becomes that window's first responder; undocked into
    /// a titled window of its own, that window becomes key.
    static func giveKeys(to w: NSWindow, in window: NSWindow) {
        if let holder = holder(of: w), holder.window === window {
            if let render = EmbeddedPages.renderView(in: holder) { window.makeFirstResponder(render) }
        } else if w.isVisible, w.styleMask.contains(.titled) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// For cra://debug?devToolsShown: whether the pointer reaches the docked frontend at its toolbar, its middle and its
    /// splitter (2 pt from the page), as Chromium decides it: a Chromium view takes a click or a mouse move only when the
    /// window's hit test at that point lands on that view (-[RenderWidgetHostViewCocoa shouldIgnoreMouseEvent:]). One
    /// "1" per point, else the class of the view in the way; nil without a docked frontend beside the page.
    static func debugHits(_ holder: Holder, page: NSView) -> String? {
        guard let window = holder.window, let content = window.contentView, let area = holder.superview,
              page.superview === area else { return nil }
        // DevTools' own part of the area: beside the page (right, left) or under or over it (bottom, top).
        guard let dev = devToolsRect(holder, page: page) else { return nil }
        let p = page.frame
        let edge: NSPoint
        if abs(dev.maxY - p.minY) < 0.5 { edge = NSPoint(x: dev.midX, y: dev.maxY - 2) }        // under the page
        else if abs(dev.minY - p.maxY) < 0.5 { edge = NSPoint(x: dev.midX, y: dev.minY + 2) }   // over it
        else if abs(dev.maxX - p.minX) < 0.5 { edge = NSPoint(x: dev.maxX - 2, y: dev.midY) }   // left of it
        else { edge = NSPoint(x: dev.minX + 2, y: dev.midY) }                                   // right of it
        // The area isn't flipped: its top is maxY.
        let points = [NSPoint(x: dev.midX, y: dev.maxY - 12), NSPoint(x: dev.midX, y: dev.midY), edge]
        return points.map { point -> String in
            let inWindow = area.convert(point, to: nil)
            guard let hit = content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow) else { return "none" }
            let render = NSStringFromClass(type(of: hit)) == "RenderWidgetHostViewCocoa"
            return render && hit.isDescendant(of: holder) ? "1" : NSStringFromClass(type(of: hit))
        }.joined(separator: ",")
    }

    /// DevTools' own part of the area beside the page (the frontend's minus the page's), nil when the page fills it.
    static func devToolsRect(_ holder: Holder, page: NSView) -> NSRect? {
        let h = holder.frame, p = page.frame
        if p.height < h.height - 1 {
            return p.minY > h.minY + 0.5 ? NSRect(x: h.minX, y: h.minY, width: h.width, height: p.minY - h.minY)
                                         : NSRect(x: h.minX, y: p.maxY, width: h.width, height: h.maxY - p.maxY)
        }
        if p.width < h.width - 1 {
            return p.minX > h.minX + 0.5 ? NSRect(x: h.minX, y: h.minY, width: p.minX - h.minX, height: h.height)
                                         : NSRect(x: p.maxX, y: h.minY, width: h.maxX - p.maxX, height: h.height)
        }
        return nil
    }

    /// For cra://debug?devtoolsClick: a click in the middle of the docked frontend, through the window as AppKit delivers
    /// a real one (its hit test, then Chromium's view). One click must be enough: in Chrome the page and DevTools share
    /// a window, and the first click into DevTools both lands and gives them the keys.
    static func debugClick(_ holder: Holder, page: NSView) {
        guard let window = holder.window, let area = holder.superview, let dev = devToolsRect(holder, page: page) else { return }
        let point = area.convert(NSPoint(x: dev.midX, y: dev.midY), to: nil)
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                 pressure: type == .leftMouseUp ? 0 : 1) else { continue }
            window.sendEvent(event)
        }
    }

    /// Lays out `area`'s page views in `page` and, with a frontend in the area, the frontend over all of `page` and the
    /// page views over the room it left (`placeholder`; all of `page` until the frontend reports one).
    static func place(in area: NSView, page: NSRect, placeholder: DevToolsPlaceholder?) {
        guard let holder = holder(in: area) else {
            EmbeddedPages.place(area.subviews, in: page)
            return
        }
        if holder.frame != page { holder.frame = page }
        let pageViews = area.subviews.filter { $0 !== holder }
        EmbeddedPages.place(pageViews, in: placeholder?.pageRect(in: page) ?? page)
    }
}
