import AppKit
import ObjectiveC

/// Chromium stops a quit under way with `-[NSApp cancelTerminate:]` (a page's "Leave site?" ▸
/// Stay; chrome_browser_application_mac::CancelTerminate). CraApplication answers it in the
/// bridge, which the app doesn't see. Cra's one-quit-at-a-time rule (QuitRequests, #426) needs to:
/// otherwise the next ⌘Q would go ahead without "Quit Cra?".
enum ChromiumQuitCancel {
    private typealias CancelIMP = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    /// Once NSApp is CraApplication. `cancelled` runs after the bridge's own handling.
    @MainActor static func install(_ cancelled: @escaping @MainActor () -> Void) {
        let selector = NSSelectorFromString("cancelTerminate:")
        guard let app: AnyClass = object_getClass(NSApp), let method = class_getInstanceMethod(app, selector) else {
            CraLog.note("quit: \(String(describing: object_getClass(NSApp))) has no cancelTerminate:, a cancelled quit isn't seen")
            return
        }
        let original = unsafeBitCast(method_getImplementation(method), to: CancelIMP.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { app, sender in
            original(app, selector, sender)
            if Thread.isMainThread { MainActor.assumeIsolated { cancelled() } } else { DispatchQueue.main.async { cancelled() } }
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
