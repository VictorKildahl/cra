import AppKit

/// The mask over the sidebar's space pages, on real Core Animation layers (PagerMask, #679).
@main
enum PagerMaskTests {
    private static var checks = 0

    /// Core Animation eases a property only on a layer that is on its way to the screen: an offscreen window's.
    @MainActor private static var host: NSView = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
        return view
    }()

    @MainActor
    static func main() {
        followsTheColumnAtOnce()
        theDownloadsFadeStillEases()
        print("PagerMaskTests: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    /// A pager's layer with the mask on it, sized for the Library's column as it was before it left.
    @MainActor
    private static func maskedPager(width: CGFloat) -> (CALayer, CAGradientLayer) {
        let pager = CALayer()
        let mask = CAGradientLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pager.frame = CGRect(x: 0, y: 0, width: width, height: 700)
        mask.frame = CGRect(x: 0, y: -14, width: width, height: 714)
        pager.mask = mask
        host.layer!.addSublayer(pager)
        CATransaction.commit()
        CATransaction.flush()
        return (pager, mask)
    }

    private static let opaque = Array(repeating: CGColor(gray: 0, alpha: 1), count: 4)
    private static let fade: [NSNumber] = [0, 0.6, 0.7, 1]

    // promise: #679
    /// kcussiefil's 120 fps recording: out of a Library a hidden sidebar opened, the column narrows from the
    /// Library's 417 pt to the tab list's 270 as it hides, and the next space's column (at 270 on the strip)
    /// showed at the screen's edge, cut away from the right as the mask eased in after it. The mask's size
    /// follows the column at once now.
    @MainActor
    private static func followsTheColumnAtOnce() {
        let (_, mask) = maskedPager(width: 417)
        PagerMask.place(mask, frame: CGRect(x: 0, y: -14, width: 270, height: 714), locations: [0, 1, 1, 1], colors: opaque, opening: false)
        expect(!PagerMask.trails(mask), "the mask narrows with the column, not after it (keys: \(mask.animationKeys() ?? []))")
        expect(mask.frame.width == 270, "the mask is the column's width")
        // Widening (into the Library, or a drag of the edge) and a taller list move it at once too.
        PagerMask.place(mask, frame: CGRect(x: 0, y: -14, width: 417, height: 800), locations: [0, 1, 1, 1], colors: opaque, opening: false)
        expect(!PagerMask.trails(mask), "the mask widens and grows with the column at once")
    }

    // promise: #679
    /// The downloads list over the tab list still fades in and out on its own ease (DownloadsTrayMask).
    @MainActor
    private static func theDownloadsFadeStillEases() {
        let (_, mask) = maskedPager(width: 270)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.locations = [0, 1, 1, 1]
        mask.colors = opaque
        CATransaction.commit()
        let clear = CGColor(gray: 0, alpha: 0)
        PagerMask.place(mask, frame: mask.frame, locations: fade, colors: [opaque[0], opaque[0], clear, clear], opening: true)
        let eased = mask.animation(forKey: "locations") as? CABasicAnimation
        expect(eased != nil && mask.animation(forKey: "colors") != nil, "opening the list fades the tab list's end out")
        expect(abs((eased?.duration ?? 0) - 0.18) < 0.001, "opening takes the list's 0.18 s")
        PagerMask.place(mask, frame: mask.frame, locations: [0, 1, 1, 1], colors: opaque, opening: false)
        expect(abs(((mask.animation(forKey: "locations") as? CABasicAnimation)?.duration ?? 0) - 0.13) < 0.001,
               "closing takes the list's 0.13 s")
    }
}
