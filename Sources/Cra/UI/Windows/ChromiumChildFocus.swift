import AppKit
import ObjectiveC

@MainActor
enum ChromiumChildFocus {
    private static let embedded = NSHashTable<NSWindow>.weakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()
    private typealias MainIMP = @convention(c) (NSWindow, Selector) -> Bool

    static func attach(_ window: NSWindow) {
        embedded.add(window)
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
                if embedded.contains(window), window.parent != nil { return false }
                return original(window, sel)
            }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
