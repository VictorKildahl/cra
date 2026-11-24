import AppKit
import CraCEF

/// Reads a page's toolbar colour off its pixels (ToolbarSample: the top-right corner, as Arc does, #629).
///
/// No `clip`: a clipped Page.captureScreenshot makes Chromium emulate the clip on the live page,
/// which flashes it (BrowserManager.captureSnapshot). Without one it copies the frame on screen;
/// only the few pixels of the patch are then cropped and converted to sRGB, off the main thread.
@MainActor
enum ToolbarSampler {
    /// Chromium's classic scroll bar, the capture's right edge while "Show scroll bars" is Always.
    static var scrollbarWidth: Double {
        NSScroller.preferredScrollerStyle == .legacy ? Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)) : 0
    }

    /// `completion` gets "#RRGGBB", on the main thread; it isn't called when nothing could be read
    /// (no page, an Easel, a failed capture). `background` is the page's own background as the engine reported it
    /// ("" or nil before it has one). A reading of only the canvas a page shows before its first frame is taken
    /// again a few times (ToolbarSample.readsOnlyTheCanvas): a white page under dark websites read black.
    static func sample(_ browser: CraBrowser, background: @escaping @MainActor () -> String? = { nil }, attempt: Int = 0,
                       completion: @escaping @MainActor (String) -> Void) {
        let scale = Double(browser.containerView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let scrollbar = scrollbarWidth
        browser.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","optimizeForSpeed":true}"#) { [weak browser] shot, _ in
            guard let shot else { return }
            DispatchQueue.global(qos: .utility).async {
                let hex = (try? JSONSerialization.jsonObject(with: Data(shot.utf8)) as? [String: Any])
                    .flatMap { $0["data"] as? String }.flatMap { Data(base64Encoded: $0) }
                    .flatMap { corner(of: $0, scale: scale, scrollbarWidth: scrollbar) }
                guard let hex else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard attempt < ToolbarSample.canvasRetries,
                              ToolbarSample.readsOnlyTheCanvas(reading: hex, canvas: canvasHex, background: background()) else {
                            completion(hex)
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + ToolbarSample.canvasRetryDelay) {
                            MainActor.assumeIsolated {
                                // A page that has gone on to load something else is sampled at that load's end.
                                guard let browser, !browser.isLoading else { return }
                                sample(browser, background: background, attempt: attempt + 1, completion: completion)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The canvas a page shows before its first frame (CraBrowser.pageCanvasColor) as "#RRGGBB".
    private static var canvasHex: String {
        guard let c = CraBrowser.pageCanvasColor.usingColorSpace(.sRGB) else { return "" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    nonisolated private static func corner(of png: Data, scale: Double, scrollbarWidth: Double) -> String? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let p = ToolbarSample.patch(imageWidth: image.width, imageHeight: image.height, scale: scale, scrollbarWidth: scrollbarWidth),
              let crop = image.cropping(to: CGRect(x: p.x, y: p.y, width: p.width, height: p.height)),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: p.width * 4,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let bytes = ctx.data else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: p.width, height: p.height))
        let rgba = Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: p.width * p.height * 4))
        return ToolbarSample.hex(rgba: rgba)
    }
}
