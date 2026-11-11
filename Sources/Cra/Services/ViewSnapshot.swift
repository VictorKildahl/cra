import AppKit

/// Component snapshots (scripts/scenario.sh `snapshot`): a view of the running window, found by its
/// class, drawn into a PNG from its layer tree at 2x. Behind-window blur and page content are
/// not part of a layer tree, so the picture holds Cra's own drawing only: geometry, ink, fills.
@MainActor
enum ViewSnapshot {
    /// "PaneToolbarView" or "PaneToolbarView,1": the first (or nth) view of that class on screen
    /// in the window (else in the first other window that has one), left to right and top to bottom (the pager keeps other spaces' columns
    /// laid out beside the visible one).
    static func find(_ spec: String, in window: NSWindow?) -> NSView? {
        let parts = spec.split(separator: ",").map(String.init)
        guard let name = parts.first, let root = window?.contentView?.superview ?? window?.contentView else { return nil }
        var found: [NSView] = []
        func walk(_ v: NSView) {
            if String(describing: type(of: v)) == name, !v.isHiddenOrHasHiddenAncestor, !v.visibleRect.isEmpty,
               v.convert(v.bounds, to: nil).intersects(root.bounds) { found.append(v) }
            v.subviews.forEach(walk)
        }
        walk(root)
        found.sort {
            let a = $0.convert($0.bounds, to: nil), b = $1.convert($1.bounds, to: nil)
            return (a.minX, -a.maxY) < (b.minX, -b.maxY)
        }
        let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return index < found.count ? found[index] : nil
    }

    /// The view `find` picks, drawn to a PNG at `path`. The references are 2x: on a 1x display the
    /// text and images are drawn at 1x and only scaled up, so that drawing goes to `<name>.1x.png`
    /// instead, and scripts/scenario.sh says so rather than comparing it.
    static func write(_ spec: String, in window: NSWindow?, to path: String) {
        // A view in a panel of its own (the Little Window's "Open in" menu) is found in any window.
        guard let view = find(spec, in: window) ?? NSApp.windows.lazy.compactMap({ find(spec, in: $0) }).first,
              let png = render(view) else {
            CraLog.note("snapshot: no visible \(spec)")
            return
        }
        // Where it is, from the window's top left as clickAt counts, for a scenario's clicks.
        if let w = view.window {
            let r = view.convert(view.bounds, to: nil)
            CraLog.note("snapshot: \(spec) at \(Int(r.minX)),\(Int(w.frame.height - r.maxY)) size \(Int(r.width))x\(Int(r.height))")
        }
        var out = path
        if let scale = view.window?.backingScaleFactor, scale < 2, path.hasSuffix(".png") {
            out = String(path.dropLast(4)) + ".1x.png"
            CraLog.note("snapshot: \(spec) is on a \(Int(scale))x display; written to \(out)")
        }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { CraLog.note("snapshot: \(error.localizedDescription)") }
    }

    private static func render(_ view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let layer = view.layer else { return nil }
        let scale: CGFloat = 2
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // The context's origin is at the bottom left; a flipped view's layer draws from the top.
        if layer.isGeometryFlipped || view.isFlipped {
            ctx.translateBy(x: 0, y: view.bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
