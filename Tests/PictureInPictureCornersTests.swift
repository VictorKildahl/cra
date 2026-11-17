import AppKit

/// The Picture in Picture hover controls stay inside the window's rounded corners (GitHub #463).
/// The real controls view in a transparent window like the overlay, drawn off screen and read back
/// through the window server; no CEF, so the chrome the controls call is stubbed below.
@main
enum PictureInPictureCornersTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        hoverLayerKeepsTheCorners()
        print("Picture in Picture corners: \(checks) checks passed")
    }

    // promise: #463
    /// Chromium's window is clipped to 6 pt continuous corners, but the dark layer the controls
    /// fade in over it filled the overlay's whole rectangle, so on hover it stood out past each
    /// corner as a grey square tip. Shown, the corner pixels stay clear while the frame's edges
    /// and middle are dimmed, at every size class.
    @MainActor
    private static func hoverLayerKeepsTheCorners() {
        for size in [NSSize(width: 240, height: 135), NSSize(width: 360, height: 203), NSSize(width: 640, height: 360)] {
            let (w, controls) = window(size)
            controls.layer?.opacity = 1   // what the fade-in on hover ends at
            let name = "\(Int(size.width))×\(Int(size.height))"
            let px = alphas(w)
            expect(px.corners.allSatisfy { $0 == 0 }, "\(name) hover layer is clear at the corners: \(px.corners)")
            expect(px.edges.allSatisfy { $0 > 50 }, "\(name) hover layer dims up to the edges: \(px.edges)")
            w.orderOut(nil)
        }
    }

    // MARK: Helpers

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// Made the way `PictureInPictureOverlay` is: borderless, clear and unshadowed, the controls
    /// filling its content view.
    @MainActor
    private static func window(_ size: NSSize) -> (NSWindow, PictureInPictureControlsView) {
        let w = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let controls = PictureInPictureControlsView(frame: root.bounds)
        controls.autoresizingMask = [.width, .height]
        root.addSubview(controls)
        w.contentView = root
        w.setFrameOrigin(NSPoint(x: -6000, y: 300))
        controls.layoutSubtreeIfNeeded()
        return (w, controls)
    }

    private typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let capture: CaptureFn = {
        // The Swift name is marked unavailable; the window server still serves a process its own windows.
        let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
        return unsafeBitCast(dlsym(cg, "CGWindowListCreateImage"), to: CaptureFn.self)
    }()

    /// The alpha of the window's four corner pixels and of four points along its edges and its
    /// middle, clear of the buttons, as the window server composites it.
    @MainActor
    private static func alphas(_ w: NSWindow) -> (corners: [Int], edges: [Int]) {
        w.orderFront(nil)
        w.display()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming
        guard let image = capture(.null, 1 << 3, UInt32(w.windowNumber), 1 << 0)?.takeRetainedValue() else {
            expect(false, "the window server returned the window's pixels")
            return ([], [])
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let a = { (p: (Int, Int)) in Int(((rep.colorAt(x: p.0, y: p.1)?.alphaComponent ?? -1) * 255).rounded()) }
        // Where the window's pixels are in the capture: an off-screen window on 1x displays came back
        // with an extra row and half-covered outer pixels (240×137 for 240×135), so the box is found
        // along the middle row and column rather than taken to be the whole image.
        let (midX, midY) = (image.width / 2, image.height / 2)
        let cols = (0..<image.width).filter { a(($0, midY)) > 0 }, rows = (0..<image.height).filter { a((midX, $0)) > 0 }
        guard let left = cols.first, let right = cols.last, let top = rows.first, let bottom = rows.last else {
            expect(false, "the window has pixels in the capture")
            return ([], [])
        }
        let (w, h) = (right - left, bottom - top)
        // Edge points a quarter of the way along, off the top bar's buttons and the centre cluster, one
        // pixel inside the box (the outermost pixel is anti-aliased on a 1x screen).
        let edges = [(left + w / 4, top + 1), (left + 1, top + h * 3 / 4), (left + w * 3 / 4, bottom - 1),
                     (right - 1, top + h * 3 / 4), (left + w / 2, top + h / 4)]
        return ([(left, top), (right, top), (left, bottom), (right, bottom)].map(a), edges.map(a))
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

// MARK: Stubs for what the controls call in the app

struct PictureInPictureActions {
    var backToTab: () -> Void
    var togglePlayback: () -> Void
    var skip: (Double) -> Void = { _ in }
    var seek: (Double) -> Void = { _ in }
    var close: () -> Void
    var minimize: () -> Void = {}
}

@MainActor
final class PictureInPictureChrome {
    static let shared = PictureInPictureChrome()
    var actions: PictureInPictureActions?
    var isPlaying = false
}

enum CraLog {
    static func note(_ message: String) {}
}

final class ArcTooltipAnchorView: NSView {
    var text = ""
    static func attach(to control: NSView, help: String) -> ArcTooltipAnchorView { ArcTooltipAnchorView() }
}
