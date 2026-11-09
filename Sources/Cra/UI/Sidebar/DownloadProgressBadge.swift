import AppKit

/// The badge on the Library button's download bin while downloads run (#272), after Arc 1.172's
/// DownloadProgressBadge (BaseHomeComponents). Its fields: progress, a ring with its own opacity,
/// an icon by name and size, a completion mark that scales and fades in, and an overall scale and
/// opacity; the ring's track is the DownloadProgressBarBackground colour. Arc's sizes and timings
/// were not observed: these are Cra's, on the bin's corner.
@MainActor
final class DownloadProgressBadgeView: NSView {
    static let size: CGFloat = 16
    private let disc = CAShapeLayer()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let arrow = CALayer()
    private let check = CALayer()
    private var shown: Double?
    private var hideWork: DispatchWorkItem?
    var colors = SidebarColors() { didSet { if colors.isDark != oldValue.isDark { paint() } } }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        guard let layer else { return }
        let bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        disc.path = CGPath(ellipseIn: bounds, transform: nil)
        // The ring starts at 12 o'clock and runs clockwise (the layer is flipped: y down).
        let ringPath = CGMutablePath()
        ringPath.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: Self.size / 2 - 2.25,
                        startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        for l in [track, ring] {
            l.path = ringPath
            l.fillColor = nil
            l.lineWidth = 1.5
            l.lineCap = .round
        }
        ring.strokeEnd = 0
        for l in [arrow, check] {
            l.frame = bounds.insetBy(dx: 4.5, dy: 4.5)
            l.contentsGravity = .resizeAspect
        }
        check.opacity = 0
        for l in [disc, track, ring, arrow, check] { layer.addSublayer(l) }
        layer.opacity = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Downloads")
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func paint() {
        let ink: NSColor = colors.isDark ? .white : .black
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.fillColor = (colors.isDark ? NSColor(white: 0.16, alpha: 1) : .white).cgColor
        disc.shadowColor = NSColor.black.cgColor
        disc.shadowOpacity = 0.18
        disc.shadowRadius = 1.5
        disc.shadowOffset = CGSize(width: 0, height: 0.5)
        track.strokeColor = ink.withAlphaComponent(0.15).cgColor
        ring.strokeColor = ink.withAlphaComponent(0.85).cgColor
        arrow.contents = Self.symbol("arrow.down", ink: ink.withAlphaComponent(0.85), scale: scale)
        check.contents = Self.symbol("checkmark", ink: ink.withAlphaComponent(0.85), scale: scale)
        for l in [arrow, check] { l.contentsScale = scale }
        CATransaction.commit()
    }

    private static func symbol(_ name: String, ink: NSColor, scale: CGFloat) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold).applying(.init(paletteColors: [ink]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
    }

    /// `progress` of the downloads still running, nil once none is; `finished` when the last one
    /// ended with a file (the check), not failed or cancelled (the badge just goes).
    func show(progress: Double?, finished: Bool) {
        guard let layer else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let progress {
            hideWork?.cancel()
            hideWork = nil
            CATransaction.begin()
            CATransaction.setAnimationDuration(reduce ? 0 : 0.2)
            if shown == nil {
                // In: the whole badge scales up from 0.6 as it fades in, ring and arrow showing.
                ring.opacity = 1
                track.opacity = 1
                arrow.opacity = 1
                check.opacity = 0
                check.transform = CATransform3DIdentity
                if !reduce { pop(layer, from: 0.6) }
                layer.opacity = 1
            }
            ring.strokeEnd = progress
            CATransaction.commit()
            shown = progress
            return
        }
        guard shown != nil else { return }
        shown = nil
        guard finished else { fadeOut(after: 0); return }
        // Done: the ring fills and fades, the arrow gives way to a check that scales in.
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduce ? 0 : 0.2)
        ring.strokeEnd = 1
        ring.opacity = 0
        track.opacity = 0
        arrow.opacity = 0
        check.opacity = 1
        CATransaction.commit()
        if !reduce { pop(check, from: 0.4) }
        fadeOut(after: 1.2)
    }

    private func pop(_ l: CALayer, from scale: CGFloat) {
        let a = CASpringAnimation(keyPath: "transform.scale")
        a.fromValue = scale
        a.toValue = 1
        a.damping = 14
        a.stiffness = 260
        a.duration = a.settlingDuration
        l.add(a, forKey: "pop")
    }

    private func fadeOut(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shown == nil, let layer = self.layer else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2)
                layer.opacity = 0
                CATransaction.commit()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
