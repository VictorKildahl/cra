import AppKit
import ObjectiveC

/// Chromium keeps its own child windows from becoming main ("Dialogs and bubbles shouldn't take
/// large shadows away from their parent", -[NativeWidgetMacNSWindow canBecomeMainWindow]), but it
/// only knows the parents it made. A Peek's or Little Window's page is a Chromium window Cra hangs
/// on its window with addChildWindow, so a click in the page made it main: the browser window
/// under a Peek lost its active shadow and coloured traffic lights. Arc's Peek is a card inside
/// the browser window, which stays main. For windows attached here the rule covers AppKit parents
/// too; they still take the keyboard.
@MainActor
enum ChromiumChildFocus {
    private static let pages = NSHashTable<NSWindow>.weakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()
    private typealias MainIMP = @convention(c) (NSWindow, Selector) -> Bool

    /// Registers a page window hung on a Cra window; if it is main already, hands main back to
    /// the nearest ancestor that can take it.
    static func attach(_ window: NSWindow) {
        pages.add(window)
        patch(type(of: window))
        guard window.isMainWindow else { return }
        var ancestor = window.parent
        while let parent = ancestor {
            if parent.canBecomeMain { parent.makeMain(); return }
            ancestor = parent.parent
        }
    }

    private static func patch(_ cls: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        let sel = #selector(getter: NSWindow.canBecomeMain)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: MainIMP.self)
        let block: @convention(block) (NSWindow) -> Bool = { window in
            MainActor.assumeIsolated {
                if pages.contains(window), window.parent != nil { return false }
                return original(window, sel)
            }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
