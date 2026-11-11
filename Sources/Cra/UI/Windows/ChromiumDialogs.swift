import AppKit
import ObjectiveC

/// Chromium's window-modal dialogs (an extension's install prompt, the prompt to remove one) get
/// no parent in Cra, so Chromium shows them free-standing: against the screen, unmovable, with
/// macOS's title bar over the prompt's title (CraCore `ChromiumDialog`, GitHub #349). Cra shows
/// each over its browser window where a sheet hangs, without the title bar, and keeps it there as
/// a child window, above the pages. Chromium still owns it: its buttons, keys and closing.
///
/// Chromium orders such a dialog in with makeKeyAndOrderFront: while Cra is active and below the
/// main window while it isn't, and AppKit posts nothing for either, so the dialog is caught where
/// both pass: -orderWindow:relativeTo: on Chromium's window class. It is framed before it shows.
@MainActor
enum ChromiumDialogs {
    /// The browser window a new dialog goes over.
    private static var owner: () -> NSWindow? = { nil }
    private static let framed = NSHashTable<NSWindow>.weakObjects()
    private static var patched = false

    static func start(owner: @escaping () -> NSWindow?) {
        self.owner = owner
        patch()
    }

    /// The dialogs over `window`, last among its children so they stay above its pages.
    static func dialogs(over window: NSWindow) -> [NSWindow] {
        framed.allObjects.filter { $0.parent === window && $0.isVisible }
    }

    /// A readout for scenarios: every window-modal Chromium dialog showing, framed or not, with
    /// whether it is on its screen, over a Cra window and clear of the title bar.
    static func readout() -> String {
        let dialogs = NSApp.windows.filter {
            $0.isVisible && NSStringFromClass(type(of: $0)) == ChromiumDialog.windowClass
                && $0.styleMask.rawValue == ChromiumDialog.windowModalStyle
        }
        guard !dialogs.isEmpty else { return "Chromium dialogs: none" }
        return "Chromium dialogs: " + dialogs.map { w in
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(w.frame) }
            let titleBarHidden = w.titlebarAppearsTransparent && w.titleVisibility == .hidden
            return "frame=\(NSStringFromRect(w.frame)) over=\(w.parent.map { NSStringFromRect($0.frame) } ?? "none")"
                + " onScreen=\(onScreen) titleBarHidden=\(titleBarHidden)"
        }.joined(separator: "; ")
    }

    private static func willOrderIn(_ w: NSWindow) {
        guard !framed.contains(w),
              ChromiumDialog.isParentless(className: NSStringFromClass(type(of: w)), styleMask: w.styleMask.rawValue,
                                          isSheet: w.isSheet, hasParent: w.parent != nil),
              let owner = owner(), owner.isVisible, owner !== w else { return }
        framed.add(w)
        // Chromium lays its content out from the window's top (full-size content view): without
        // the bar's fill and title it shows all of it, as a sheet does.
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(button)?.isHidden = true
        }
        place(w, over: owner)
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { note in
            // The install prompt grows when it shows a field: it stays centred under the bar.
            MainActor.assumeIsolated {
                guard let w = note.object as? NSWindow, let parent = w.parent else { return }
                place(w, over: parent)
            }
        }
        // Attached once Chromium's own ordering is done: addChildWindow orders it again.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard w.isVisible, w.parent == nil, owner.isVisible else { return }
                owner.addChildWindow(w, ordered: .above)
                CraLog.note("Chromium dialog \(w.windowNumber) shown over window \(owner.windowNumber) at \(NSStringFromRect(w.frame))")
            }
        }
    }

    private static func place(_ w: NSWindow, over owner: NSWindow) {
        let screen = (owner.screen ?? w.screen ?? NSScreen.main)?.visibleFrame ?? owner.frame
        let titleBar = owner.frame.height - owner.contentLayoutRect.maxY
        let frame = ChromiumDialog.frame(size: w.frame.size, over: owner.frame, titleBarHeight: titleBar, screen: screen)
        if w.frame != frame { w.setFrame(frame, display: true) }
    }

    private typealias OrderIMP = @convention(c) (AnyObject, Selector, Int, Int) -> Void

    private static func patch() {
        guard !patched, let cls = NSClassFromString(ChromiumDialog.windowClass) else { return }
        patched = true
        let sel = #selector(NSWindow.order(_:relativeTo:))
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: OrderIMP.self)
        let block: @convention(block) (AnyObject, Int, Int) -> Void = { obj, mode, other in
            if mode != NSWindow.OrderingMode.out.rawValue, let w = obj as? NSWindow {
                MainActor.assumeIsolated { willOrderIn(w) }
            }
            original(obj, sel, mode, other)
        }
        let imp = imp_implementationWithBlock(block)
        // Add on Chromium's class when it only inherits the method, else replace its own.
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
