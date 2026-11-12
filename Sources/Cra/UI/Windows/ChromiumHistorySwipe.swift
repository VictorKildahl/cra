import AppKit
import ObjectiveC

/// Chromium's two-finger history swipe over a page, and a Magic Mouse's (HistorySwiper, through
/// ChromeRenderWidgetHostViewMacDelegate). It starts only when the page's own history can move
/// (`canNavigateInDirection:onWindow:`) and then moves the page itself
/// (`navigateInDirection:onWindow:`); Cra's Back never hears of it. So on a tab a link opened,
/// where Back closes the tab and shows the one it came from (#273), the swipe did nothing
/// (GitHub #370). Arc's Chromium asks the app when the page can't go back
/// (WebContentsUIDelegate::CanExternallyNavigate, then WillExternallyNavigate); here the same two
/// methods ask the tab's window then, and BackToReferrer.swipeBack decides. Forward stays
/// Chromium's.
@MainActor
enum ChromiumHistorySwipe {
    private typealias CanIMP = @convention(c) (AnyObject, Selector, Int32, NSWindow?) -> Bool
    private typealias GoIMP = @convention(c) (AnyObject, Selector, Int32, NSWindow?) -> Void
    private typealias ViewIMP = @convention(c) (AnyObject, Selector) -> NSView?

    /// history_swiper::NavigationDirection's kBackwards (kForwards is 1).
    private static let backwards: Int32 = 0
    private static let canSel = NSSelectorFromString("canNavigateInDirection:onWindow:")
    private static let goSel = NSSelectorFromString("navigateInDirection:onWindow:")
    private static let viewSel = NSSelectorFromString("viewThatWantsHistoryOverlay")

    /// After Chromium is loaded (the delegate class is in its framework).
    static func install() {
        guard let cls = NSClassFromString("ChromeRenderWidgetHostViewMacDelegate"),
              let can = class_getInstanceMethod(cls, canSel), let go = class_getInstanceMethod(cls, goSel),
              class_getInstanceMethod(cls, viewSel) != nil else {
            CraLog.note("history swipe: Chromium's swipe delegate not found, a swipe back can't close a link's tab")
            return
        }
        let canSel = canSel, goSel = goSel, backwards = backwards
        let originalCan = unsafeBitCast(method_getImplementation(can), to: CanIMP.self)
        let originalGo = unsafeBitCast(method_getImplementation(go), to: GoIMP.self)
        let canBlock: @convention(block) (AnyObject, Int32, NSWindow?) -> Bool = { delegate, direction, window in
            if originalCan(delegate, canSel, direction, window) { return true }
            guard direction == backwards else { return false }
            return MainActor.assumeIsolated { closeToReferrer(delegate) != nil }
        }
        let goBlock: @convention(block) (AnyObject, Int32, NSWindow?) -> Void = { delegate, direction, window in
            guard direction == backwards, !originalCan(delegate, canSel, direction, window),
                  let close = MainActor.assumeIsolated({ closeToReferrer(delegate) }) else {
                return originalGo(delegate, goSel, direction, window)
            }
            // After the swipe's own handling of this event: the tab's page goes with it.
            DispatchQueue.main.async { close() }
        }
        method_setImplementation(can, imp_implementationWithBlock(canBlock))
        method_setImplementation(go, imp_implementationWithBlock(goBlock))
    }

    /// The swipe back's close on the tab whose page `delegate` serves, when that page has nothing
    /// behind it; nil for a page that isn't a tab on screen (DevTools, an extension's popup) or a
    /// tab Back doesn't close.
    private static func closeToReferrer(_ delegate: AnyObject) -> (() -> Void)? {
        guard let method = class_getInstanceMethod(type(of: delegate), viewSel),
              let view = unsafeBitCast(method_getImplementation(method), to: ViewIMP.self)(delegate, viewSel),
              let app = NSApp.delegate as? AppDelegate else { return nil }
        for main in app.mainWindows {
            if let id = main.browsers.visibleTabID(ofPageView: view) { return main.swipeBackClose(id) }
        }
        return nil
    }

    /// `cra://debug?swipeBack=`: asks the page's swipe delegate what Chromium's swipe asks before
    /// it starts (`can`), and with `perform` calls what it calls at the end, as a real swipe back
    /// over the page in `root` would. "no page" or "no delegate" when there's nothing to ask.
    static func debugSwipeBack(in root: NSView, perform: Bool) -> String {
        guard let page = EmbeddedPages.renderView(in: root) else { return "no page" }
        guard let ivar = class_getInstanceVariable(type(of: page), "_responderDelegate"),
              let raw = object_getIvar(page, ivar) else { return "no delegate" }
        let delegate = raw as AnyObject
        guard let can = class_getInstanceMethod(type(of: delegate), canSel),
              let go = class_getInstanceMethod(type(of: delegate), goSel) else { return "no delegate" }
        let answer = unsafeBitCast(method_getImplementation(can), to: CanIMP.self)(delegate, canSel, backwards, page.window)
        if perform, answer { unsafeBitCast(method_getImplementation(go), to: GoIMP.self)(delegate, goSel, backwards, page.window) }
        return "can=\(answer ? 1 : 0)"
    }
}
