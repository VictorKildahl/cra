import AppKit
import ObjectiveC

/// Chromium's page and DevTools windows use a frame view derived from NSThemeFrame, so
/// macOS clips them to its window corner radius (about 18 pt on macOS 26) even when they
/// are borderless. Docked inside Cra's card they must be square; the card's own rounded
/// bottom corners come from the content layer's mask. This overrides the frame view's
/// corner queries for windows registered here only; every other window keeps the system
/// behaviour.
///
/// macOS 27 rounds them as well (#400: about 10 pt on all four corners on 27.2.1, so the
/// white toolbar and card showed around a dark DevTools panel), through its corner
/// configurations (`NSView.cornerConfiguration`, public from macOS 27) and the window's own
/// radius rather than only the frame view's queries. A registered window therefore reports
/// square at every level: its frame view, its window, and its content view, which gets no
/// configuration so AppKit leaves Cra's 6 pt mask on that layer alone.
@MainActor
enum ChromiumWindowCorners {
    private static let squared = NSHashTable<NSWindow>.weakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()

    static func setSquare(_ square: Bool, for window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        patchFrameView(type(of: frameView))
        patchWindow(type(of: window))
        if let content = window.contentView { patchContentView(type(of: content)) }
        let changed = squared.contains(window) != square
        if square { squared.add(window) } else { squared.remove(window) }
        guard changed else { return }
        let refresh = NSSelectorFromString("_cornerMaskChanged")
        if window.responds(to: refresh) { window.perform(refresh) }
        // macOS 27 caches each view's resolved corners until this is called.
        let invalidate = NSSelectorFromString("invalidateCornerConfiguration")
        for view in [frameView, window.contentView].compactMap({ $0 }) where view.responds(to: invalidate) {
            view.perform(invalidate)
        }
        frameView.needsDisplay = true
        window.invalidateShadow()
    }

    static func isSquare(_ object: AnyObject) -> Bool {
        if let w = object as? NSWindow { return squared.contains(w) }
        guard let v = object as? NSView, let w = v.window else { return false }
        return squared.contains(w)
    }

    /// Only a window's content view: a subview of the same class in a squared window keeps
    /// whatever corners AppKit gives it.
    private static func isSquareContent(_ object: AnyObject) -> Bool {
        guard let v = object as? NSView, let w = v.window, w.contentView === v else { return false }
        return squared.contains(w)
    }

    private static func patchFrameView(_ cls: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        overrideBool(cls, "_shouldRoundCornersForSurface", squareValue: false)
        overrideBool(cls, "topCornerRounded", squareValue: false)
        overrideBool(cls, "bottomCornerRounded", squareValue: false)
        overrideFloat(cls, "_cornerRadius", squareValue: 0)
        overrideFloat(cls, "_getCachedWindowCornerRadius", squareValue: 0)
        // Linked against a pre-26 SDK (release builds on GitHub's macos-15 runners), macOS 26
        // ignores the queries above and masks the window with a 12 pt corner image of its own,
        // which rounded the page's top corners under the toolbar. No mask means square.
        overrideObject(cls, "_cornerMask", squareValue: nil)
        // The window's shape as a corner configuration: private on macOS 26, public on 27. A
        // nil configuration means "unconfigured", not square, so these need real values.
        if let square = squareConfiguration {
            overrideObject(cls, "_cornerConfiguration", squareValue: square)
            overrideObject(cls, "cornerConfiguration", squareValue: square)
        }
        if let zero = zeroRadii { overrideObject(cls, "effectiveCornerRadii", squareValue: zero) }
    }

    private static func patchWindow(_ cls: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        overrideBool(cls, "_shouldRoundCornersForSurface", squareValue: false)
        overrideBool(cls, "bottomCornerRounded", squareValue: false)
        for name in ["_cornerRadius", "_effectiveCornerRadius", "_topCornerRadius", "_bottomCornerRadius"] {
            overrideFloat(cls, name, squareValue: 0)
        }
        overrideObject(cls, "_cornerMask", squareValue: nil)
        overrideObject(cls, "_cornerPath", squareValue: nil)
        // What AppKit hands the window server: a radius set while squared is set as 0.
        overrideFloatSetter(cls, "_setCornerRadius:")
        overrideFloatSetter(cls, "_setEffectiveCornerRadius:")
    }

    private static func patchContentView(_ cls: AnyClass) {
        guard patchedClasses.insert(ObjectIdentifier(cls)).inserted else { return }
        overrideObject(cls, "cornerConfiguration", squareValue: nil, when: isSquareContent)
        overrideObject(cls, "effectiveCornerRadii", squareValue: nil, when: isSquareContent)
    }

    /// Square corners as macOS 27's public API spells them (a fixed radius of 0), or macOS
    /// 26's private `+squareCorners`. Nil where neither exists, and then the queries aren't touched.
    static let squareConfiguration: AnyObject? = {
        guard let configuration = NSClassFromString("NSViewCornerConfiguration") else { return nil }
        let uniform = NSSelectorFromString("configurationWithUniformRadius:")
        let fixed = NSSelectorFromString("fixedRadius:")
        if let radiusClass = NSClassFromString("NSViewCornerRadius"),
           let fixedMethod = class_getClassMethod(radiusClass, fixed),
           class_getClassMethod(configuration, uniform) != nil {
            typealias FixedIMP = @convention(c) (AnyClass, Selector, CGFloat) -> Unmanaged<AnyObject>?
            let make = unsafeBitCast(method_getImplementation(fixedMethod), to: FixedIMP.self)
            if let zero = make(radiusClass, fixed, 0)?.takeUnretainedValue(),
               let config = (configuration as AnyObject).perform(uniform, with: zero)?.takeUnretainedValue() {
                return config
            }
        }
        let square = NSSelectorFromString("squareCorners")
        guard class_getClassMethod(configuration, square) != nil else { return nil }
        return (configuration as AnyObject).perform(square)?.takeUnretainedValue()
    }()

    private static let zeroRadii: AnyObject? = {
        guard let radii = NSClassFromString("NSViewCornerRadii") else { return nil }
        let zero = NSSelectorFromString("zero")
        guard class_getClassMethod(radii, zero) != nil else { return nil }
        return (radii as AnyObject).perform(zero)?.takeUnretainedValue()
    }()

    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
    private typealias FloatIMP = @convention(c) (AnyObject, Selector) -> CGFloat
    private typealias ObjectIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias FloatSetterIMP = @convention(c) (AnyObject, Selector, CGFloat) -> Void

    private static func overrideBool(_ cls: AnyClass, _ name: String, squareValue: Bool) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
        let block: @convention(block) (AnyObject) -> Bool = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        install(cls, sel, method, types, imp_implementationWithBlock(block))
    }

    private static func overrideFloat(_ cls: AnyClass, _ name: String, squareValue: CGFloat) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: FloatIMP.self)
        let block: @convention(block) (AnyObject) -> CGFloat = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        install(cls, sel, method, types, imp_implementationWithBlock(block))
    }

    private static func overrideFloatSetter(_ cls: AnyClass, _ name: String) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: FloatSetterIMP.self)
        let block: @convention(block) (AnyObject, CGFloat) -> Void = { obj, value in
            original(obj, sel, MainActor.assumeIsolated { isSquare(obj) } ? 0 : value)
        }
        install(cls, sel, method, types, imp_implementationWithBlock(block))
    }

    /// `when` picks the objects that get `squareValue` (default: anything in a squared window).
    private static func overrideObject(_ cls: AnyClass, _ name: String, squareValue: AnyObject?,
                                       when test: @escaping @MainActor (AnyObject) -> Bool = isSquare) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ObjectIMP.self)
        let block: @convention(block) (AnyObject) -> Unmanaged<AnyObject>? = { obj in
            MainActor.assumeIsolated { test(obj) } ? squareValue.map { Unmanaged.passUnretained($0) } : original(obj, sel)
        }
        install(cls, sel, method, types, imp_implementationWithBlock(block))
    }

    /// Add on the subclass when it only inherits the method, else replace its own.
    private static func install(_ cls: AnyClass, _ sel: Selector, _ method: Method, _ types: UnsafePointer<CChar>, _ imp: IMP) {
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
