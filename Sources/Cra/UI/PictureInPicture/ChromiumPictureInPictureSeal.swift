import AppKit
import ObjectiveC

/// PictureInPictureInput's AppKit side (the rule is CraCore's): Chromium's video PiP window, once
/// Cra has laid its overlay over it, drops every input event and refuses the key, so Chrome's own
/// controls never show under Arc's (GitHub #460). `ignoresMouseEvents` and Chromium's
/// `preventKeyWindow` (#262) stay as the first line; this holds whatever still gets through, and
/// logs it once per kind, so a report says how it got there.
///
/// Chromium's window class (NativeWidgetMacNSWindow, which every Chromium widget uses) gets
/// `sendEvent:` and `canBecomeKeyWindow` replaced once; they act only for sealed windows and hand
/// everything else to Chromium's own. The window's class itself is left alone: AppKit observes
/// windows by key-value observing, and that swaps in a class of its own.
@MainActor
enum ChromiumPictureInPictureSeal {
    /// Changed only on the main thread; read by the replaced methods, which pass anything off it on.
    nonisolated(unsafe) private static let sealed = NSHashTable<NSWindow>.weakObjects()

    nonisolated private static func isSealedHere(_ window: NSWindow) -> Bool {
        Thread.isMainThread && sealed.contains(window)
    }
    private static var patched: Set<ObjectIdentifier> = []

    static func isSealed(_ window: NSWindow) -> Bool { sealed.contains(window) }

    static func seal(_ window: NSWindow) {
        guard !sealed.contains(window) else { return }
        // `type(of:)` asks the object (-class), which is Chromium's class even under a KVO subclass.
        let cls: AnyClass = type(of: window)
        if !patched.contains(ObjectIdentifier(cls)) {
            guard patch(cls) else { return CraLog.note("pip: couldn't seal \(NSStringFromClass(cls))") }
            patched.insert(ObjectIdentifier(cls))
        }
        sealed.add(window)
    }

    private static func patch(_ cls: AnyClass) -> Bool {
        let sendSelector = #selector(NSWindow.sendEvent(_:))
        let keySelector = #selector(getter: NSWindow.canBecomeKey)
        guard let sendTypes = class_getInstanceMethod(cls, sendSelector).flatMap(method_getTypeEncoding),
              let keyTypes = class_getInstanceMethod(cls, keySelector).flatMap(method_getTypeEncoding) else { return false }

        typealias Send = @convention(c) (NSWindow, Selector, NSEvent) -> Void
        let chromiumSend = unsafeBitCast(class_getMethodImplementation(cls, sendSelector), to: Send.self)
        let send: @convention(block) (NSWindow, NSEvent) -> Void = { window, event in
            if isSealedHere(window), !PictureInPictureInput.chromiumTakes(kind(of: event.type)) {
                MainActor.assumeIsolated { noteDropped(event.type) }
            } else {
                chromiumSend(window, sendSelector, event)
            }
        }

        typealias CanBecomeKey = @convention(c) (NSWindow, Selector) -> Bool
        let chromiumCanBecomeKey = unsafeBitCast(class_getMethodImplementation(cls, keySelector), to: CanBecomeKey.self)
        let canBecomeKey: @convention(block) (NSWindow) -> Bool = { window in
            isSealedHere(window) ? PictureInPictureInput.chromiumCanBecomeKey : chromiumCanBecomeKey(window, keySelector)
        }

        // Replaces the class's own, or adds one over the inherited (whose code `chromium…` holds).
        class_replaceMethod(cls, sendSelector, imp_implementationWithBlock(send), sendTypes)
        class_replaceMethod(cls, keySelector, imp_implementationWithBlock(canBecomeKey), keyTypes)
        return true
    }

    nonisolated static func kind(of type: NSEvent.EventType) -> PictureInPictureInput.Kind {
        switch type {
        case .mouseMoved: .mouseMove
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged, .pressure: .mouseButton
        case .mouseEntered, .mouseExited: .trackingArea
        case .cursorUpdate: .cursorUpdate
        case .scrollWheel: .scroll
        case .keyDown, .keyUp, .flagsChanged: .key
        case .appKitDefined, .systemDefined, .applicationDefined, .periodic: .system
        default: .gesture   // magnify, rotate, swipe, smart magnify, touches, tablet, quick look
        }
    }

    /// Kinds dropped so far, each logged once: what reached Chromium's window despite the overlay.
    private static var dropped: Set<UInt> = []

    private static func noteDropped(_ type: NSEvent.EventType) {
        if dropped.insert(type.rawValue).inserted {
            CraLog.note("pip: Chromium's window got event type \(type.rawValue), dropped (Cra \(NSApp.isActive ? "active" : "inactive"))")
        }
    }
}
