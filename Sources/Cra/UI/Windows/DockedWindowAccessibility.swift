import AppKit
import ObjectiveC

/// Cra's page, DevTools, floating sidebar and overlays are child windows docked over the main
/// window, and AppKit tells accessibility clients each one is a window of its own. Window
/// managers find the window to move through accessibility, so they tore the docked part off
/// Cra's window: Moves walks AXParent from the element under the pointer to the first AXWindow
/// and found the page or the sidebar panel (#391); Rectangle, Magnet and Raycast take the
/// focused window, which is the page whenever it has the keyboard. Arc is one window.
///
/// A child window that AppKit would report as an AXWindow reports as an AXGroup inside its
/// parent: its AXParent is the parent window, its AXWindow and AXTopLevelUIElement the
/// top-level window, and its parent lists it among its children so VoiceOver still reaches the
/// page. The app's AXWindows leave it out, and its focused and main windows are the top-level
/// window. Moving or resizing a docked window through accessibility moves or resizes the
/// top-level window by as much. Sheets and popovers keep their own roles; a window taken off its
/// parent is a window again.
@MainActor
enum DockedWindowAccessibility {
    private static var installed = false
    private static var patchedClasses = Set<ObjectIdentifier>()
    private typealias ObjectIMP = @convention(c) (NSObject, Selector) -> AnyObject?
    private typealias AttachIMP = @convention(c) (NSWindow, Selector, NSWindow, Int) -> Void

    /// Patches NSWindow's addChildWindow so every window that gets docked (and its parent)
    /// answers as above from then on, and the application's window list.
    static func install() {
        guard !installed else { return }
        installed = true
        patchAttach()
        patchApplication(type(of: NSApplication.shared))
    }

    /// The window a window manager should move for `window`: its top-level ancestor.
    static func topLevel(_ window: NSWindow) -> NSWindow {
        var top = window
        while let parent = top.parent { top = parent }
        return top
    }

    /// Whether `window` answers as a group inside its parent; `role` is what AppKit says it is.
    private static func isDocked(_ window: NSWindow, role: AnyObject?) -> Bool {
        window.parent != nil && !window.isSheet && window.sheetParent == nil
            && role as? String == NSAccessibility.Role.window.rawValue
    }

    private static func patchAttach() {
        let sel = #selector(NSWindow.addChildWindow(_:ordered:))
        guard let method = class_getInstanceMethod(NSWindow.self, sel) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: AttachIMP.self)
        let block: @convention(block) (NSWindow, NSWindow, Int) -> Void = { parent, child, place in
            original(parent, sel, child, place)
            MainActor.assumeIsolated {
                patchWindow(type(of: parent))
                patchWindow(type(of: child))
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// The attributes a docked window answers differently, by attribute name and by getter.
    private static let getters: [(NSAccessibility.Attribute, String)] = [
        (.role, "accessibilityRole"), (.roleDescription, "accessibilityRoleDescription"),
        (.subrole, "accessibilitySubrole"), (.parent, "accessibilityParent"), (.window, "accessibilityWindow"),
        (.topLevelUIElement, "accessibilityTopLevelUIElement"), (.children, "accessibilityChildren"),
    ]

    /// Clients ask by attribute name (`accessibilityAttributeValue:`), which NSWindow answers on
    /// its own without its getters, and code asks the getters; both are patched to one answer.
    private static func patchWindow(_ cls: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        let appKit = byName(cls)
        let roleOf = { (w: NSWindow) in appKit(w, .role) }
        replaceByName(cls) { object, attribute, answer in
            (object as? NSWindow).map { answerFor($0, attribute, appKit: answer, role: roleOf($0)) } ?? answer
        }
        for (attribute, getter) in getters {
            override(cls, getter) { w, answer in answerFor(w, attribute, appKit: answer, role: roleOf(w)) }
        }
        forwardMoves(cls, appKit: appKit, roleOf: roleOf)
    }

    /// Web content names the page window as its AXWindow (Chromium answers that, not AppKit), and
    /// tools that move "the window of the element under the pointer" set that window's position or
    /// size. On a docked window the change goes to the top-level window, by the same amount.
    private static func forwardMoves(_ cls: AnyClass, appKit: @escaping (NSObject, NSAccessibility.Attribute) -> AnyObject?,
                                     roleOf: @escaping (NSWindow) -> AnyObject?) {
        typealias SetIMP = @convention(c) (NSObject, Selector, AnyObject?, NSString) -> Void
        let sel = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: SetIMP.self)
        let block: @convention(block) (NSObject, AnyObject?, NSString) -> Void = { object, value, name in
            let forwarded = MainActor.assumeIsolated { () -> Bool in
                let attribute = NSAccessibility.Attribute(rawValue: name as String)
                guard attribute == .position || attribute == .size, let w = object as? NSWindow,
                      isDocked(w, role: roleOf(w)), let wanted = value as? NSValue,
                      let now = appKit(w, attribute) as? NSValue else { return false }
                // By frame, not by the top window's own setter: AppKit ignores that one while it
                // is inside this call once a client has asked the docked window for its AXWindow.
                // In-process AX positions are the frame's origin, so the delta applies as is.
                let top = topLevel(w)
                var frame = top.frame
                if attribute == .position {
                    frame.origin.x += wanted.pointValue.x - now.pointValue.x
                    frame.origin.y += wanted.pointValue.y - now.pointValue.y
                } else {
                    let top = frame.maxY
                    frame.size.width += wanted.sizeValue.width - now.sizeValue.width
                    frame.size.height += wanted.sizeValue.height - now.sizeValue.height
                    frame.origin.y = top - frame.height  // a resize keeps the top-left corner, as AX does
                }
                topLevel(w).setFrame(frame, display: true)
                return true
            }
            if !forwarded { original(object, sel, value, name) }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    /// What `window` answers for `attribute`, given AppKit's own answer and role.
    private static func answerFor(_ w: NSWindow, _ attribute: NSAccessibility.Attribute, appKit answer: AnyObject?,
                                  role: AnyObject?) -> AnyObject? {
        if attribute == .children {
            let inside = (w.childWindows ?? []).filter { child in
                child.parent === w && child.accessibilityAttributeValue(.role) as? String == NSAccessibility.Role.group.rawValue
            }
            guard !inside.isEmpty else { return answer }
            let children = (answer as? [AnyObject]) ?? []
            return (children + inside.filter { d in !children.contains { $0 === d } }) as NSArray
        }
        guard isDocked(w, role: role) else { return answer }
        switch attribute {
        case .role: return NSAccessibility.Role.group.rawValue as NSString
        case .roleDescription: return NSAccessibility.Role.group.description(with: nil) as NSString?
        case .subrole: return nil
        case .parent: return w.parent
        case .window, .topLevelUIElement: return topLevel(w)
        default: return answer
        }
    }

    private static func patchApplication(_ cls: AnyClass) {
        let attributes: [(NSAccessibility.Attribute, String)] = [
            (.windows, "accessibilityWindows"), (.focusedWindow, "accessibilityFocusedWindow"),
            (.mainWindow, "accessibilityMainWindow"),
        ]
        let answer = { (attribute: NSAccessibility.Attribute, appKit: AnyObject?) -> AnyObject? in
            if attribute == .windows {
                guard let windows = appKit as? [AnyObject] else { return appKit }
                return windows.filter { element in
                    guard let w = element as? NSWindow, w.parent != nil else { return true }
                    return w.accessibilityAttributeValue(.role) as? String != NSAccessibility.Role.group.rawValue
                } as NSArray
            }
            guard attributes.contains(where: { $0.0 == attribute }) else { return appKit }
            return (appKit as? NSWindow).map(topLevel) ?? appKit
        }
        replaceByName(cls) { _, name, appKit in answer(name, appKit) }
        for (attribute, getter) in attributes {
            replace(cls, getter) { _, appKit in answer(attribute, appKit) }
        }
    }

    private typealias ByNameIMP = @convention(c) (NSObject, Selector, NSString) -> AnyObject?
    private static let byNameSelector = NSSelectorFromString("accessibilityAttributeValue:")

    /// `accessibilityAttributeValue:` as `cls` answers it now, before any patch of ours.
    private static func byName(_ cls: AnyClass) -> (NSObject, NSAccessibility.Attribute) -> AnyObject? {
        let sel = byNameSelector
        guard let method = class_getInstanceMethod(cls, sel) else { return { _, _ in nil } }
        let original = unsafeBitCast(method_getImplementation(method), to: ByNameIMP.self)
        return { original($0, sel, $1.rawValue as NSString) }
    }

    /// Replaces `accessibilityAttributeValue:` on `cls` with `body(self, attribute, AppKit's answer)`.
    private static func replaceByName(
        _ cls: AnyClass, _ body: @escaping @MainActor (NSObject, NSAccessibility.Attribute, AnyObject?) -> AnyObject?
    ) {
        let sel = byNameSelector
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ByNameIMP.self)
        let block: @convention(block) (NSObject, NSString) -> AnyObject? = { object, name in
            let answer = original(object, sel, name)
            return MainActor.assumeIsolated { body(object, NSAccessibility.Attribute(rawValue: name as String), answer) }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    /// Replaces the object getter `name` on `cls` with `body(self, what it answered before)`.
    /// A class that only inherits the getter gets a method of its own, so its superclass and
    /// the other classes keep theirs.
    private static func override(_ cls: AnyClass, _ name: String,
                                 _ body: @escaping @MainActor (NSWindow, AnyObject?) -> AnyObject?) {
        replace(cls, name) { object, answer in (object as? NSWindow).map { body($0, answer) } ?? answer }
    }

    private static func replace(_ cls: AnyClass, _ name: String,
                                _ body: @escaping @MainActor (NSObject, AnyObject?) -> AnyObject?) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ObjectIMP.self)
        let block: @convention(block) (NSObject) -> AnyObject? = { object in
            let answer = original(object, sel)
            return MainActor.assumeIsolated { body(object, answer) }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
