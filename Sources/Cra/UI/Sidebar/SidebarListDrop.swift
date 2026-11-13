import AppKit

/// What releasing a sidebar drag over the space's list would do right now. The
/// rows read it to draw the live preview (insertion line, rows easing apart,
/// the row a drop would combine with) and SpaceListView applies it on drop.
struct SidebarListDrop: Equatable {
    enum Target: Equatable {
        /// Before the child at `index` of `parent` (`index == count` appends).
        case insert(parent: UUID, index: Int)
        /// A split of this tab and the dragged one (Arc's drag-to-combine, pinned or Today, #191);
        /// the dragged tab takes the left pane when `leading`, else the right.
        case split(with: UUID, leading: Bool)
        /// Into a folder or a split row.
        case into(UUID)
    }

    struct Line: Equatable {
        var y: CGFloat
        var minX: CGFloat
        var maxX: CGFloat
    }

    /// nil for a link dragged in from a page or another app, which opens as a new tab (#419).
    var draggedID: UUID?
    /// nil while the drop would leave the item where it is.
    var target: Target?
    /// Insertion line in the list's coordinate space.
    var line: Line?
    /// The rows on either side of the line, nudged apart.
    var rowAbove: UUID?
    var rowBelow: UUID?
}

/// Scrolls a space's list while a drag hovers near its top or bottom edge, so
/// with a long pinned list everything past the fold (Today included) stays in reach.
@MainActor
final class DragAutoscroller {
    /// Edge band, and the speed at the very edge in points per second.
    static let band: CGFloat = 48
    static let maxSpeed: CGFloat = 900

    weak var anchor: NSView?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    /// Starts or stops scrolling for where the pointer is now.
    func update() {
        guard speed() != 0 else { stop(); return }
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // A drag keeps the run loop in event-tracking mode.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func speed() -> CGFloat {
        guard NSEvent.pressedMouseButtons != 0, let sv = anchor?.enclosingScrollView, let window = sv.window else { return 0 }
        let p = sv.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let fromTop = sv.isFlipped ? p.y : sv.bounds.height - p.y
        let fromBottom = sv.bounds.height - fromTop
        guard p.x >= 0, p.x <= sv.bounds.width, fromTop >= 0, fromBottom >= 0 else { return 0 }
        if fromTop < Self.band { return -Self.maxSpeed * (1 - fromTop / Self.band) }
        if fromBottom < Self.band { return Self.maxSpeed * (1 - fromBottom / Self.band) }
        return 0
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        let v = speed()
        guard v != 0, let sv = anchor?.enclosingScrollView else { stop(); return }
        let clip = sv.contentView
        var origin = clip.bounds.origin
        origin.y += v * dt * (sv.documentView?.isFlipped ?? true ? 1 : -1)
        let r = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        guard r.origin != clip.bounds.origin else { return }
        clip.scroll(to: r.origin)
        sv.reflectScrolledClipView(clip)
    }
}

/// A tab row while another tab hovers over its middle, drawn as the split the drop makes:
/// the row splits open and the dragged tab slides into a dashed pane on the side it will take
/// (the split row's own layout), moving across when the pointer crosses the row's middle.
@MainActor
final class CombineDropPreview: NSView {
    enum Kind: Equatable { case split(leading: Bool) }

    private let kind: Kind
    private let target: SidebarItem
    private let dragged: SidebarItem
    private let depth: Int
    private let palette: SpacePalette
    private let colors: SidebarColors
    private let favicons: FaviconCache
    private let card = NSView()
    private var didOpen = false

    init(kind: Kind, target: SidebarItem, dragged: SidebarItem, depth: Int, palette: SpacePalette, favicons: FaviconCache) {
        self.kind = kind
        self.target = target
        self.dragged = dragged
        self.depth = depth
        self.palette = palette
        colors = SidebarColors(palette)
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        card.wantsLayer = true
        if let l = card.layer {
            l.cornerRadius = CraMetrics.rowCorner
            l.cornerCurve = .continuous
            l.backgroundColor = colors.selectedFill.cgColor
            l.borderWidth = 1.5
            l.shadowColor = NSColor.black.cgColor
            l.shadowOpacity = palette.isDark ? 0.25 : 0.1
        }
        addSubview(card)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `withAnimation(.spring(duration: 0.34, bounce: 0.22)) { open = true }` on appear.
    private static func spring(_ layer: CALayer?, _ key: String, from: Any, to: Any) {
        let a = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.22)
        a.keyPath = key
        a.fromValue = from
        a.toValue = to
        a.duration = a.settlingDuration
        layer?.add(a, forKey: key)
    }

    override func layout() {
        super.layout()
        guard !didOpen, bounds.width > 0 else { return }
        didOpen = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.frame = bounds
        if let l = card.layer {
            l.borderColor = colors.textPrimary.withAlphaComponent(0.35).cgColor
            l.shadowRadius = 6
            l.shadowOffset = CGSize(width: 0, height: -2)
            Self.spring(l, "borderColor", from: colors.textPrimary.withAlphaComponent(0).cgColor, to: l.borderColor!)
            Self.spring(l, "shadowRadius", from: 2.0, to: 6.0)
            Self.spring(l, "shadowOffset", from: CGSize(width: 0, height: -1), to: l.shadowOffset)
            // .scaleEffect(0.97 → 1), from the card's centre.
            let small = bounds.insetBy(dx: bounds.width * 0.015, dy: bounds.height * 0.015)
            Self.spring(l, "bounds.size", from: small.size, to: bounds.size)
            Self.spring(l, "position", from: CGPoint(x: small.minX, y: small.minY), to: l.position)
        }
        switch kind {
        case .split(let leading): buildSplit(leading: leading)
        }
        CATransaction.commit()
    }

    // MARK: Split

    private func cell(_ item: SidebarItem, width: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let icon = SidebarFaviconView()
        icon.show(favicons.image(forKey: item.tab?.iconKey), flip: favicons.glyphIsDark(forKey: item.tab?.iconKey) == palette.isDark, colors: colors)
        let h = bounds.height
        icon.frame = NSRect(x: SplitRowMetrics.cellInset + SplitRowMetrics.favicon, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        v.addSubview(icon)
        let label = NSTextField.sidebarLabel(size: 14)
        label.stringValue = item.displayTitle
        label.textColor = colors.textPrimary
        // HStack(spacing: 8) after 8 pt, Spacer(minLength: 2), 4 pt trailing.
        let x = SplitRowMetrics.cellInset + SplitRowMetrics.favicon + CraMetrics.favicon + 11
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - 17) / 2, width: max(0, width - x - 14) + 2 * SidebarText.inset, height: 17)
        v.addSubview(label)
        return v
    }

    private func buildSplit(leading: Bool) {
        let x0 = CGFloat(depth) * CraMetrics.indent
        let w = max(0, bounds.width - x0), h = bounds.height
        let pane = max(0, (w - 1) / 2)
        let targetCell = cell(target, width: w - pane)
        let draggedCell = cell(dragged, width: pane)
        // The dragged half: a dashed box 4 pt in, clipped while it opens.
        let dash = CAShapeLayer()
        dash.fillColor = colors.hoverFill.cgColor
        dash.strokeColor = colors.textPrimary.withAlphaComponent(0.45).cgColor
        dash.lineWidth = 1.25
        dash.lineDashPattern = [4, 3]
        // Never narrower than its corners: CGPath refuses radii wider than half the rect.
        let r = CraMetrics.rowCorner - 3
        let box = { (width: CGFloat) in CGPath(roundedRect: NSRect(x: 4.625, y: 4.625, width: max(2 * r, width - 9.25), height: max(2 * r, h - 9.25)),
                                               cornerWidth: r, cornerHeight: r, transform: nil) }
        dash.path = box(pane)
        draggedCell.layer?.insertSublayer(dash, at: 0)
        draggedCell.layer?.masksToBounds = true
        addSubview(targetCell)
        addSubview(draggedCell)
        let targetOpen = NSRect(x: leading ? x0 + pane : x0, y: 0, width: w - pane, height: h)
        let draggedOpen = NSRect(x: leading ? x0 : x0 + w - pane, y: 0, width: pane, height: h)
        targetCell.frame = targetOpen
        draggedCell.frame = draggedOpen
        // Closed: the target fills the row, the dragged half is 0 wide and 12 pt outside it.
        Self.spring(targetCell.layer, "position", from: CGPoint(x: x0, y: 0), to: targetCell.layer!.position)
        Self.spring(targetCell.layer, "bounds.size.width", from: w, to: w - pane)
        let draggedFromX = leading ? x0 - 12 : x0 + w + 12
        Self.spring(draggedCell.layer, "position", from: CGPoint(x: draggedFromX, y: 0), to: draggedCell.layer!.position)
        Self.spring(draggedCell.layer, "bounds.size.width", from: 0.0, to: pane)
        Self.spring(draggedCell.layer, "opacity", from: 0.0, to: 1.0)
        Self.spring(dash, "path", from: box(9.25), to: dash.path!)
        let line = NSView(frame: NSRect(x: x0 + w / 2 - 0.5, y: SplitRowMetrics.separatorInset, width: 1, height: h - 2 * SplitRowMetrics.separatorInset))
        line.wantsLayer = true
        line.layer?.backgroundColor = colors.separator.cgColor
        addSubview(line)
        Self.spring(line.layer, "opacity", from: 0.0, to: 1.0)
    }
}
