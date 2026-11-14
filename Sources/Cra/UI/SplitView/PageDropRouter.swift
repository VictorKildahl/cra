import AppKit
import ObjectiveC

/// What decides a drag over a page before the page does: the window that shows it.
@MainActor
protocol PageDropTarget: AnyObject {
    /// The operation Cra takes the drag with at its current point, nil to leave it to the page.
    func pageDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation?
    /// Cra let go of the drag: it left, moved back onto the page's own part, or ended.
    func pageDragExited()
    func pageDragPerform(_ info: NSDraggingInfo) -> Bool
}

/// A tab or a link dragged over a page can make a split, as in Arc (`SplitViewController` is the
/// drop destination over the window's contents, GitHub #419). Chromium's page view
/// (WebContentsViewCocoa) is the destination there, so its dragging methods ask the window first:
/// where it proposes a split, Cra holds the drag; elsewhere the page gets it as before, with an
/// enter and an exit each time the drag crosses between the two. The view also takes Cra's
/// sidebar rows, which Chromium never registered for.
@MainActor
enum PageDropRouter {
    /// Page views whose current drag Cra holds.
    private static let held = NSHashTable<NSView>.weakObjects()
    /// Page views Cra just dropped on: their conclude belongs to Cra too.
    private static let dropped = NSHashTable<NSView>.weakObjects()
    private static var patched = false

    static func install(on page: NSView) {
        patch(type(of: page))
        let types = page.registeredDraggedTypes
        if !types.contains(.craSidebarItem) { page.registerForDraggedTypes(types + [.craSidebarItem]) }
    }

    /// The window controller that shows the page: its own window with the page embedded in a
    /// card, the parent of the page's Chrome window otherwise.
    static func target(of view: NSView) -> PageDropTarget? {
        guard let w = view.window else { return nil }
        return ((w.windowController as? MainWindowController) ?? (w.parent?.windowController as? MainWindowController))?.splitDrop
    }

    private typealias OpIMP = @convention(c) (AnyObject, Selector, NSDraggingInfo) -> NSDragOperation
    private typealias VoidIMP = @convention(c) (AnyObject, Selector, NSDraggingInfo?) -> Void
    private typealias BoolIMP = @convention(c) (AnyObject, Selector, NSDraggingInfo) -> Bool

    private static func patch(_ cls: AnyClass) {
        guard !patched, NSStringFromClass(cls) == "WebContentsViewCocoa" else { return }
        patched = true
        let enteredSel = #selector(NSDraggingDestination.draggingEntered(_:))
        let updatedSel = #selector(NSDraggingDestination.draggingUpdated(_:))
        let exitedSel = #selector(NSDraggingDestination.draggingExited(_:))
        let performSel = #selector(NSDraggingDestination.performDragOperation(_:))
        let prepareSel = #selector(NSDraggingDestination.prepareForDragOperation(_:))
        let concludeSel = #selector(NSDraggingDestination.concludeDragOperation(_:))
        let entered = original(cls, enteredSel, as: OpIMP.self)
        let updated = original(cls, updatedSel, as: OpIMP.self)
        let exited = original(cls, exitedSel, as: VoidIMP.self)
        let perform = original(cls, performSel, as: BoolIMP.self)
        let prepare = original(cls, prepareSel, as: BoolIMP.self)
        let conclude = original(cls, concludeSel, as: VoidIMP.self)

        // Over the page: Cra's proposal or the page's. Crossing between them tells the side
        // that loses the drag it left, and the page that gets it back that it came in.
        func route(_ obj: AnyObject, _ info: NSDraggingInfo, entering: Bool) -> NSDragOperation {
            MainActor.assumeIsolated {
                guard let view = obj as? NSView else { return [] }
                let wasHeld = held.contains(view)
                if let op = target(of: view)?.pageDragUpdated(info) {
                    if !wasHeld {
                        held.add(view)
                        if !entering { exited?(obj, exitedSel, info) }
                    }
                    return op
                }
                if wasHeld {
                    held.remove(view)
                    target(of: view)?.pageDragExited()
                    return entered?(obj, enteredSel, info) ?? []
                }
                return (entering ? entered.map { ($0, enteredSel) } : updated.map { ($0, updatedSel) })
                    .map { $0.0(obj, $0.1, info) } ?? []
            }
        }
        set(cls, enteredSel, types: "Q@:@", block: { (obj: AnyObject, info: NSDraggingInfo) -> NSDragOperation in
            route(obj, info, entering: true)
        } as @convention(block) (AnyObject, NSDraggingInfo) -> NSDragOperation)
        set(cls, updatedSel, types: "Q@:@", block: { (obj: AnyObject, info: NSDraggingInfo) -> NSDragOperation in
            route(obj, info, entering: false)
        } as @convention(block) (AnyObject, NSDraggingInfo) -> NSDragOperation)
        set(cls, exitedSel, types: "v@:@", block: { (obj: AnyObject, info: NSDraggingInfo?) in
            let mine = MainActor.assumeIsolated { () -> Bool in
                guard let view = obj as? NSView, held.contains(view) else { return false }
                held.remove(view)
                target(of: view)?.pageDragExited()
                return true
            }
            if !mine { exited?(obj, exitedSel, info) }
        } as @convention(block) (AnyObject, NSDraggingInfo?) -> Void)
        set(cls, prepareSel, types: "B@:@", block: { (obj: AnyObject, info: NSDraggingInfo) -> Bool in
            if MainActor.assumeIsolated({ (obj as? NSView).map { held.contains($0) } ?? false }) { return true }
            return prepare?(obj, prepareSel, info) ?? true
        } as @convention(block) (AnyObject, NSDraggingInfo) -> Bool)
        set(cls, performSel, types: "B@:@", block: { (obj: AnyObject, info: NSDraggingInfo) -> Bool in
            let result = MainActor.assumeIsolated { () -> Bool? in
                guard let view = obj as? NSView, held.contains(view) else { return nil }
                held.remove(view)
                dropped.add(view)
                let done = target(of: view)?.pageDragPerform(info) ?? false
                target(of: view)?.pageDragExited()
                return done
            }
            return result ?? perform?(obj, performSel, info) ?? false
        } as @convention(block) (AnyObject, NSDraggingInfo) -> Bool)
        set(cls, concludeSel, types: "v@:@", block: { (obj: AnyObject, info: NSDraggingInfo?) in
            let mine = MainActor.assumeIsolated { () -> Bool in
                guard let view = obj as? NSView, dropped.contains(view) else { return false }
                dropped.remove(view)
                return true
            }
            if !mine { conclude?(obj, concludeSel, info) }
        } as @convention(block) (AnyObject, NSDraggingInfo?) -> Void)
    }

    /// The implementation the class has now, its own or inherited; nil when it has none.
    private static func original<T>(_ cls: AnyClass, _ sel: Selector, as: T.Type) -> T? {
        class_getInstanceMethod(cls, sel).map { unsafeBitCast(method_getImplementation($0), to: T.self) }
    }

    /// Replaces the method on `cls` only: an inherited one gets an override, the superclass keeps its own.
    private static func set(_ cls: AnyClass, _ sel: Selector, types: String, block: Any) {
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types), let m = class_getInstanceMethod(cls, sel) {
            method_setImplementation(m, imp)
        }
    }
}
