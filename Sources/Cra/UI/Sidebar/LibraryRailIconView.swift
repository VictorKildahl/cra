import AppKit

/// One of the Library rail's icons: two colours, playing once when its page is picked (Arc's
/// `AnimatedPageSidebarItemView`). The drawings, the timeline and which frame shows when are
/// `LibraryRailIcons` in CraCore; this view draws that frame, on the display's refresh while it plays
/// and not at all otherwise.
@MainActor
final class LibraryRailIconView: NSView {
    let icon: LibraryRailIcon
    private var player: LibraryRailIcons.Player
    private var link: CADisplayLink?
    /// The lines' colour, and what fills them (nil: nothing).
    var primary = NSColor.white { didSet { if primary != oldValue { needsDisplay = true } } }
    var secondary: NSColor? { didSet { if secondary != oldValue { needsDisplay = true } } }
    /// The frame drawn last, and how many were drawn since the last change, for cra://debug.
    private(set) var drawnFrame = LibraryRailIcons.hoverStart
    private(set) var framesSinceChange = 0

    init(icon: LibraryRailIcon) {
        self.icon = icon
        player = LibraryRailIcons.Player(icon)
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The page was picked: the icon plays to its selection's end. With Reduce Motion, or out of a
    /// window, it stays as it is (Arc plays nothing then).
    func playSelection() {
        framesSinceChange = 0
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            player.settle()
            needsDisplay = true
            return
        }
        player.selected(at: CACurrentMediaTime())
        if link == nil {
            let l = displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
        needsDisplay = true
    }

    var isPlaying: Bool { link != nil }

    @objc private func step(_ link: CADisplayLink) {
        needsDisplay = true
        if player.isSettled(at: link.targetTimestamp) {
            link.invalidate()
            self.link = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
            player.settle()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let frame = player.frame(at: link?.targetTimestamp ?? CACurrentMediaTime())
        if frame != drawnFrame || framesSinceChange == 0 { framesSinceChange += 1 }
        drawnFrame = frame
        ctx.saveGState()
        let scale = min(bounds.width, bounds.height) / LibraryRailIcons.canvas
        ctx.translateBy(x: (bounds.width - LibraryRailIcons.canvas * scale) / 2, y: (bounds.height - LibraryRailIcons.canvas * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        func cg(_ c: NSColor) -> CGColor { c.cgColor.converted(to: space, intent: .defaultIntent, options: nil) ?? c.cgColor }
        LibraryRailIcons.draw(icon, frame: frame, in: ctx, primary: cg(primary), secondary: secondary.map(cg))
        ctx.restoreGState()
    }

    /// For cra://debug?libraryRail: the frame drawn last, and in how many frames since it was last picked.
    var readout: String {
        String(format: "%@ frame=%.0f frames=%d", icon.rawValue, drawnFrame, framesSinceChange)
    }
}
