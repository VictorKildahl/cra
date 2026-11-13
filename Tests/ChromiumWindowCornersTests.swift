import AppKit
import ObjectiveC

/// Docked page and DevTools windows stay square however AppKit asks for their corners (GitHub
/// #400). Real windows, drawn off screen and read back through the window server; no CEF.
@main
enum ChromiumWindowCornersTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        squareWhenAppKitRoundsTheWindow()
        squareAtEveryLevel()
        otherWindowsKeepTheirCorners()
        print("Chromium window corners: \(checks) checks passed")
    }

    // promise: #400
    /// macOS 27.2 clipped the docked windows to about 10 pt on all four corners, so the white
    /// toolbar and card showed around a dark DevTools panel. Here AppKit's own window radius
    /// (`-[NSWindow _setCornerRadius:]`, which rounds a borderless window on macOS 26 too) stands
    /// in for it: a squared window keeps every corner pixel, as docked (borderless) and still titled.
    @MainActor
    private static func squareWhenAppKitRoundsTheWindow() {
        for docked in [true, false] {
            let w = window(docked: docked)
            ChromiumWindowCorners.setSquare(true, for: w)
            setCornerRadius(w, 12)
            let corners = cornerAlphas(w)
            expect(corners.allSatisfy { $0 == 255 }, "\(docked ? "docked" : "titled") window square with a radius set: \(corners)")
            w.orderOut(nil)
        }
    }

    /// Every corner query reports square: the frame view's configuration (private on macOS 26,
    /// public on 27) resolves to 0, the window's radii are 0, and the content view has no
    /// configuration, so AppKit leaves Cra's own 6 pt mask on its layer alone.
    @MainActor
    private static func squareAtEveryLevel() {
        for docked in [true, false] {
            let w = window(docked: docked)
            let name = docked ? "docked" : "titled"
            ChromiumWindowCorners.setSquare(true, for: w)
            let frameView = w.contentView!.superview!
            for query in ["_cornerConfiguration", "cornerConfiguration"] where frameView.responds(to: NSSelectorFromString(query)) {
                let radii = resolved(frameView, query)
                expect(radii == nil || radii == [0, 0, 0, 0], "\(name) frame view \(query) resolves square: \(radii ?? [])")
            }
            for query in ["_cornerRadius", "_effectiveCornerRadius", "_topCornerRadius", "_bottomCornerRadius"] {
                if let r = float(w, query) { expect(r == 0, "\(name) window \(query) is 0, not \(r)") }
            }
            let content = w.contentView!
            if content.responds(to: NSSelectorFromString("cornerConfiguration")) {
                expect(content.perform(NSSelectorFromString("cornerConfiguration")) == nil, "\(name) content view has no corner configuration")
            }
            w.orderOut(nil)
        }
    }

    /// Only registered windows change: another window keeps macOS's rounded corners, and so
    /// does an undocked DevTools window once it is no longer square.
    @MainActor
    private static func otherWindowsKeepTheirCorners() {
        let plain = window(docked: false)
        expect((float(plain, "_cornerRadius") ?? 0) > 0, "an unregistered titled window keeps its radius")
        expect(cornerAlphas(plain).allSatisfy { $0 == 0 }, "an unregistered titled window keeps its rounded corners")
        plain.orderOut(nil)

        let undocked = window(docked: false)
        ChromiumWindowCorners.setSquare(true, for: undocked)
        ChromiumWindowCorners.setSquare(false, for: undocked)
        expect((float(undocked, "_cornerRadius") ?? 0) > 0, "an undocked window gets its radius back")
        expect(cornerAlphas(undocked).allSatisfy { $0 == 0 }, "an undocked window gets its rounded corners back")
        undocked.orderOut(nil)

        let docked = window(docked: true)
        ChromiumWindowCorners.setSquare(true, for: docked)
        ChromiumWindowCorners.setSquare(false, for: docked)
        setCornerRadius(docked, 12)
        expect(cornerAlphas(docked).allSatisfy { $0 == 0 }, "a radius set on a window that is no longer square applies")
        docked.orderOut(nil)
    }

    // MARK: Helpers

    /// Chromium's windows are NSWindow subclasses; this one also stays where it's put, off screen.
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// Made titled like CEF makes it; docked strips it the way `DevToolsWindowChrome.dock` does.
    @MainActor
    private static func window(docked: Bool) -> NSWindow {
        let w = OffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                                styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        if docked {
            w.styleMask.remove([.titled, .resizable])
            w.styleMask.insert(.fullSizeContentView)
        }
        w.hasShadow = false
        w.backgroundColor = .black
        w.setFrameOrigin(NSPoint(x: -6000, y: 300))
        return w
    }

    private typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let capture: CaptureFn = {
        // The Swift name is marked unavailable; the window server still serves a process its own windows.
        let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
        return unsafeBitCast(dlsym(cg, "CGWindowListCreateImage"), to: CaptureFn.self)
    }()

    /// The alpha of the window's four corner pixels, as the window server composites it.
    @MainActor
    private static func cornerAlphas(_ w: NSWindow) -> [Int] {
        w.orderFront(nil)
        w.display()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming
        guard let image = capture(.null, 1 << 3, UInt32(w.windowNumber), 1 << 0)?.takeRetainedValue() else {
            expect(false, "the window server returned the window's pixels")
            return []
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let (x, y) = (image.width - 1, image.height - 1)
        return [(0, 0), (x, 0), (0, y), (x, y)].map { Int(((rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? -1) * 255).rounded()) }
    }

    @MainActor
    private static func setCornerRadius(_ w: NSWindow, _ radius: CGFloat) {
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let sel = NSSelectorFromString("_setCornerRadius:")
        guard let imp = class_getMethodImplementation(type(of: w), sel), w.responds(to: sel) else {
            expect(false, "NSWindow has _setCornerRadius:")
            return
        }
        unsafeBitCast(imp, to: Setter.self)(w, sel, radius)
    }

    private static func float(_ object: AnyObject, _ name: String) -> CGFloat? {
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGFloat
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: object), sel) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: Getter.self)(object, sel)
    }

    /// The four radii the configuration gives a view filling its container; nil without one.
    private static func resolved(_ view: NSView, _ query: String) -> [CGFloat]? {
        guard let config = view.perform(NSSelectorFromString(query))?.takeUnretainedValue() else { return nil }
        if let radii = (view.responds(to: NSSelectorFromString("effectiveCornerRadii")) ? view.perform(NSSelectorFromString("effectiveCornerRadii"))?.takeUnretainedValue() : nil) as? NSObject {
            return ["topLeft", "topRight", "bottomLeft", "bottomRight"].map { (radii.value(forKey: $0) as? CGFloat) ?? -1 }
        }
        typealias Resolve = @convention(c) (AnyObject, Selector, CGRect, CGRect, AnyObject?, Bool) -> Unmanaged<AnyObject>?
        let sel = NSSelectorFromString("_resolvedCornerRadiiForSubviewRect:containerRect:containerCornerRadii:isFlipped:")
        guard let method = class_getInstanceMethod(type(of: config), sel),
              let zero = (NSClassFromString("NSViewCornerRadii") as AnyObject).perform(NSSelectorFromString("zero"))?.takeUnretainedValue(),
              let radii = unsafeBitCast(method_getImplementation(method), to: Resolve.self)(config, sel, view.bounds, view.bounds, zero, view.isFlipped)?.takeUnretainedValue() as? NSObject
        else { return [-1, -1, -1, -1] }
        return ["topLeft", "topRight", "bottomLeft", "bottomRight"].map { (radii.value(forKey: $0) as? CGFloat) ?? -1 }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
