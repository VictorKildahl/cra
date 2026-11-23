import AppKit

/// What the window server shows at the centre of a page, frame by frame (cra://debug?pageColours=): the colours a
/// person sees while a page opens, as runs ("000000x40 FFFFFF x9 0D1117x30"). A process may read its own windows
/// without Screen Recording access.
@MainActor
enum WindowColourProbe {
    private typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let capture: CaptureFn? = {
        // The Swift name is marked unavailable; the window server still serves a process its own windows.
        guard let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let fn = dlsym(cg, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(fn, to: CaptureFn.self)
    }()

    /// The colour at the centre of `view` as composited on screen, "RRGGBB"; nil while it has no window.
    static func colour(at view: NSView) -> String? {
        guard let window = view.window, let capture else { return nil }
        let centre = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: centre)
        // Global display coordinates run down from the top of the main display.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let rect = CGRect(x: onScreen.x.rounded(.down), y: (top - onScreen.y).rounded(.down), width: 1, height: 1)
        // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
        guard let image = capture(rect, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue(),
              let pixel = NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(pixel.redComponent), byte(pixel.greenComponent), byte(pixel.blueComponent))
    }

    /// Samples `view()` every display frame for `seconds` (waiting for it to exist), then hands back the runs.
    static func record(seconds: Double, view: @escaping @MainActor () -> NSView?, done: @escaping @MainActor (String) -> Void) {
        var runs: [(String, Int)] = []
        let end = Date().addingTimeInterval(seconds)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                if let v = view(), let c = colour(at: v) {
                    if runs.last?.0 == c { runs[runs.count - 1].1 += 1 } else { runs.append((c, 1)) }
                }
                guard Date() >= end else { return }
                timer.invalidate()
                done(runs.isEmpty ? "none" : runs.map { "\($0.0)x\($0.1)" }.joined(separator: " "))
            }
        }
    }
}
