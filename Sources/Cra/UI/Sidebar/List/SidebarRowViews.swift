import AppKit
import SwiftUI

// The rows of a space's tab list, drawn by AppKit (see SpaceListView). Each row is a plain
// layer-backed view: hover comes from the list's one tracking area, clicks and drags from the
// row's own mouse events. Rows draw what their model says and nothing else; the list rebuilds
// the models when the store changes and hands a row a new one only when it differs.

/// The palette's colours as AppKit colours, converted once per list update.
struct SidebarColors: Equatable {
    var isDark = false
    var textPrimary = NSColor.labelColor
    var textSecondary = NSColor.secondaryLabelColor
    var textTertiary = NSColor.tertiaryLabelColor
    var hoverFill = NSColor.clear
    var selectedFill = NSColor.clear
    var separator = NSColor.separatorColor
    var pillFill = NSColor.clear

    init() {}

    init(_ p: SpacePalette) {
        isDark = p.isDark
        textPrimary = NSColor(p.textPrimary)
        textSecondary = NSColor(p.textSecondary)
        textTertiary = NSColor(p.textTertiary)
        hoverFill = NSColor(p.hoverFill)
        selectedFill = NSColor(p.selectedFill)
        separator = NSColor(p.separator)
        pillFill = NSColor(p.pillFill)
    }

    /// SidebarIconButton's glyph tone outside the header (no active state).
    var glyph: NSColor { isDark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.26) }
    /// A one-colour favicon or GitHub's mark on the sidebar.
    var monoGlyph: NSColor { isDark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.85) }
}

enum SidebarSymbols {
    static func image(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    /// The tab row's ✕ (or − for a pinned tab that stays): Arc strokes two 2 pt round-capped lines
    /// 4.25 pt out from a centre on a whole point, crisp at 1x. No SF Symbol size matches it, and an
    /// NSImage drawn for it came out thinner and off-centre at 1x, so the button strokes this itself.
    static func closeMark(minus: Bool = false, centre c: CGPoint) -> CGPath {
        let d: CGFloat = 4.25
        let p = CGMutablePath()
        if minus {
            p.move(to: CGPoint(x: c.x - d, y: c.y)); p.addLine(to: CGPoint(x: c.x + d, y: c.y))
        } else {
            p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
            p.move(to: CGPoint(x: c.x - d, y: c.y + d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
        }
        return p
    }
}

extension NSImageView {
    /// Arc's refresh ⇄ stop swap, fitted frame by frame to a 120 fps capture of Arc 1.170 (30 Oct): over
    /// ~90 ms the old glyph fades while shrinking to 0.7 and the new one fades in growing from 0.7,
    /// both easing in and out. (The system's Replace transition un-draws arrow.clockwise over 0.8 s.)
    func swapSymbol(_ image: NSImage?) {
        guard let superview, window != nil, let old = self.image, image != nil else { self.image = image; return }
        let ghost = NSImageView(frame: frame)
        ghost.wantsLayer = true
        ghost.imageScaling = imageScaling
        ghost.image = old
        ghost.contentTintColor = contentTintColor
        superview.addSubview(ghost, positioned: .above, relativeTo: self)
        self.image = image
        guard let layer, let ghostLayer = ghost.layer else { ghost.removeFromSuperview(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { ghost.removeFromSuperview() }
        // A press turn still settling goes out with the old glyph; the new one starts square.
        ghostLayer.transform = layer.transform
        for key in layer.animationKeys() ?? [] where key.hasPrefix("turn") {
            if let turn = layer.animation(forKey: key) { ghostLayer.add(turn, forKey: key) }
            layer.removeAnimation(forKey: key)
        }
        layer.transform = CATransform3DIdentity
        layer.setValue(nil, forKey: "turn")
        ghostLayer.opacity = 0
        ghostLayer.add(Self.swapAnimation(ghostLayer, fadeIn: false), forKey: "swap")
        layer.add(Self.swapAnimation(layer, fadeIn: true), forKey: "swap")
        CATransaction.commit()
    }

    private static func swapAnimation(_ layer: CALayer, fadeIn: Bool) -> CAAnimationGroup {
        let c = centre(of: layer)
        var small = CATransform3DMakeTranslation(c.x, c.y, 0)
        small = CATransform3DScale(small, 0.7, 0.7, 1)
        small = CATransform3DTranslate(small, -c.x, -c.y, 0)
        // Added to whatever turn the glyph has.
        let scale = CABasicAnimation(keyPath: "transform")
        scale.isAdditive = true
        scale.fromValue = NSValue(caTransform3D: fadeIn ? small : CATransform3DIdentity)
        scale.toValue = NSValue(caTransform3D: fadeIn ? CATransform3DIdentity : small)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fadeIn ? 0 : 1
        fade.toValue = fadeIn ? 1 : 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.09
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return group
    }

    /// Arc's press on the refresh arrow (same capture): a quarter turn clockwise about the arrow's
    /// circle while the button is down, back on release, 0.15 s ease-in-out each way. As in SwiftUI a
    /// turn is added on top of one still running, so a quick click only nudges the arrow.
    func pressTurn(_ down: Bool) {
        guard let layer else { return }
        let to: CGFloat = down ? .pi / 2 : 0
        let from = layer.value(forKey: "turn") as? CGFloat ?? 0
        guard to != from else { return }
        layer.setValue(to, forKey: "turn")
        let flipped = layer.contentsAreFlipped()
        // arrow.clockwise's circle sits 1/16 of the image's height below the image's centre.
        var c = Self.centre(of: layer)
        c.y += (flipped ? 1 : -1) * (image?.size.height ?? 0) / 16
        func turned(_ angle: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(c.x, c.y, 0)
            t = CATransform3DRotate(t, flipped ? angle : -angle, 0, 0, 1)
            return CATransform3DTranslate(t, -c.x, -c.y, 0)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = turned(to)
        if window != nil {
            // Even steps of angle, eased as a whole: a single matrix tween would swing the pivot.
            let steps = 30
            let turn = CAKeyframeAnimation(keyPath: "transform")
            turn.values = (0...steps).map { NSValue(caTransform3D: turned((from - to) * CGFloat(steps - $0) / CGFloat(steps))) }
            turn.isAdditive = true
            turn.duration = 0.15
            turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            turn.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.add(turn, forKey: "turn\(turn.beginTime)")
        }
        CATransaction.commit()
    }

    /// The layer's centre relative to its anchor: AppKit keeps a view layer's anchor where it likes.
    private static func centre(of layer: CALayer) -> CGPoint {
        CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x), y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
    }
}

enum SidebarText {
    /// NSTextField draws its text this far in from its frame; labels are placed that much
    /// further left so the text lands where SwiftUI's Text put it.
    static let inset: CGFloat = 2
}

extension NSTextField {
    static func sidebarLabel(size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: size, weight: weight)
        l.lineBreakMode = .byTruncatingTail
        l.usesSingleLineMode = true
        l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true
        return l
    }
}

/// SidebarIconButton for AppKit rows: a glyph with a rounded hover fill and an Arc tooltip.
final class SidebarGlyphButton: NSView {
    var action: () -> Void
    let size: NSSize
    private let glyph = NSImageView()
    private var shownSymbol: String?
    /// Arc turns the refresh arrow while it is pressed (NSImageView.pressTurn).
    private var turnsOnPress = false
    /// Stroked instead of the image (SidebarSymbols.closeMark).
    private var mark: CAShapeLayer?
    private var markMinus = false
    private var tip: ArcTooltipAnchorView?
    private var hovering = false { didSet { refresh() } }
    var colors: SidebarColors { didSet { if colors != oldValue { refresh() } } }

    /// Header buttons follow the app's active state (nil: the plain sidebar tone).
    var active: Bool? { didSet { if active != oldValue { refresh() } } }
    var enabled = true { didSet { if enabled != oldValue { refresh() } } }
    /// Drawn in this colour instead of the sidebar's glyph tone.
    var tint: NSColor? { didSet { if tint != oldValue { refresh() } } }
    /// Keeps the hover fill while what it opened is open (the player's volume drawer).
    var highlighted = false { didSet { if highlighted != oldValue { refresh() } } }

    init(symbol: String, size: CGFloat, height: CGFloat? = nil, iconSize: CGFloat, weight: NSFont.Weight = .medium, help: String,
         optionHelp: String? = nil, colors: SidebarColors, action: @escaping () -> Void) {
        self.size = NSSize(width: size, height: height ?? min(size, 28))
        self.colors = colors
        self.action = action
        super.init(frame: NSRect(origin: .zero, size: self.size))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        glyph.image = SidebarSymbols.image(symbol, size: iconSize, weight: weight)
        shownSymbol = symbol
        glyph.imageScaling = .scaleNone
        glyph.frame = bounds
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
        if !help.isEmpty {
            tip = ArcTooltipAnchorView.attach(to: self, help: help)
            tip?.optionText = optionHelp
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `animated` swaps another symbol in the way Arc swaps refresh and stop.
    func setSymbol(_ symbol: String, iconSize: CGFloat, weight: NSFont.Weight = .medium, help: String, animated: Bool = false) {
        let image = SidebarSymbols.image(symbol, size: iconSize, weight: weight)
        if animated, shownSymbol != nil, shownSymbol != symbol {
            glyph.swapSymbol(image)
            setHelp(help)
        } else {
            setGlyph(image, help: help)
        }
        shownSymbol = symbol
        turnsOnPress = animated && symbol == "arrow.clockwise"
    }

    func setGlyph(_ image: NSImage?, help: String) {
        shownSymbol = nil
        glyph.image = image
        glyph.isHidden = false
        mark?.isHidden = true
        setHelp(help)
    }

    /// Shows the tab row's ✕ / − (SidebarSymbols.closeMark) in place of the image.
    func setCloseMark(minus: Bool, help: String) {
        if mark == nil {
            let m = CAShapeLayer()
            m.fillColor = nil
            m.lineWidth = 2
            m.lineCap = .round
            m.actions = ["path": NSNull(), "strokeColor": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(m)
            mark = m
        }
        markMinus = minus
        shownSymbol = nil
        glyph.isHidden = true
        mark?.isHidden = false
        needsLayout = true
        refresh()
        setHelp(help)
    }

    func setHelp(_ help: String) {
        if let tip { (tip.text, tip.keys) = ArcTooltipLabel.split(help) } else if !help.isEmpty { tip = ArcTooltipAnchorView.attach(to: self, help: help) }
    }

    /// Arc 1.170 draws these glyphs at roughly 26% black while the app is in the background; with
    /// the app active its header glyphs darken to ~59% black, disabled ones stay at ~24%.
    private func refresh() {
        let tint: NSColor
        if colors.isDark {
            // Arc's row ✕ is a touch brighter than its other glyphs (white 0.6 over the hover fill, 1x).
            tint = enabled ? NSColor.white.withAlphaComponent(mark != nil ? 0.6 : 0.55) : colors.textTertiary.withAlphaComponent(colors.textTertiary.alphaComponent * 0.55)
        } else if let active {
            tint = NSColor.black.withAlphaComponent(enabled && active ? 0.59 : 0.24)
        } else {
            tint = enabled ? colors.glyph : colors.textTertiary.withAlphaComponent(colors.textTertiary.alphaComponent * 0.55)
        }
        glyph.contentTintColor = self.tint ?? tint
        mark?.strokeColor = (self.tint ?? tint).cgColor
        layer?.backgroundColor = ((hovering || highlighted) && enabled ? colors.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        guard let mark else { return }
        mark.frame = bounds
        // The centre on a whole point of the window: a dragged sidebar width is fractional.
        let mid = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let centre = convert(CGPoint(x: mid.x.rounded(), y: mid.y.rounded()), from: nil)
        mark.path = SidebarSymbols.closeMark(minus: markMinus, centre: centre)
        mark.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mark?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        // A new area under the pointer gets no mouseEntered, so without assumeInside it never sends
        // the mouseExited either and the hover fill sticks (buttons moved under a resting pointer).
        let inside = window.map { visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if inside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
        if hovering != inside { hovering = inside }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A button that appears under a resting pointer (a row's hover buttons) is hovered at once.
        if let w = window { hovering = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    // Rows hide their buttons rather than remove them; a button shown again under the pointer is hovered.
    override func viewDidHide() { hovering = false }
    override func viewDidUnhide() {
        viewDidMoveToWindow()
        if mark != nil { needsLayout = true }   // the row may have scrolled while hidden
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        if mark != nil { needsLayout = true }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        if turnsOnPress, enabled { glyph.pressTurn(true) }
    }
    override func mouseDragged(with event: NSEvent) {
        if turnsOnPress, enabled { glyph.pressTurn(bounds.contains(convert(event.locationInWindow, from: nil))) }
    }
    override func mouseUp(with event: NSEvent) {
        if turnsOnPress { glyph.pressTurn(false) }
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// FaviconView for AppKit rows: the cached favicon, one-colour glyphs flipped to suit the fill,
/// a globe while there is none.
final class SidebarFaviconView: NSImageView {
    private var shown: (NSImage?, Bool, Bool)?

    init(size: CGFloat = CraMetrics.favicon) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ icon: NSImage?, flip: Bool, colors: SidebarColors) {
        if let s = shown, s.0 === icon, s.1 == flip, s.2 == colors.isDark { return }
        shown = (icon, flip, colors.isDark)
        let size = frame.width
        if let icon {
            imageScaling = .scaleProportionallyUpOrDown
            if flip {
                let t = icon.copy() as! NSImage
                t.isTemplate = true
                image = t
                contentTintColor = colors.monoGlyph
            } else {
                image = icon
                contentTintColor = nil
            }
            layer?.cornerRadius = size * 0.22
            layer?.masksToBounds = true
        } else {
            imageScaling = .scaleNone
            image = SidebarSymbols.image("globe", size: size * 0.8)
            contentTintColor = colors.textTertiary
            layer?.masksToBounds = false
        }
    }

    func showGitHubMark(colors: SidebarColors, color: NSColor? = nil) {
        shown = nil
        imageScaling = .scaleProportionallyUpOrDown
        image = GitHubMark.image
        contentTintColor = color ?? colors.monoGlyph
        layer?.masksToBounds = false
    }
}

/// Arc's folder glyph: the outline over a filled folder while closed, GitHub's mark on a live folder.
final class FolderGlyphView: NSView {
    private let fill = NSImageView()
    private let outline = NSImageView()
    private let mark = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for v in [fill, outline] {
            v.imageScaling = .scaleNone
            v.autoresizingMask = [.width, .height]
            v.frame = bounds
            addSubview(v)
        }
        fill.image = SidebarSymbols.image("folder.fill", size: 15)
        outline.image = SidebarSymbols.image("folder", size: 15)
        mark.image = GitHubMark.image
        mark.imageScaling = .scaleProportionallyUpOrDown
        addSubview(mark)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(expanded: Bool, live: Bool, tint: NSColor, fillColor: NSColor) {
        fill.isHidden = expanded
        fill.contentTintColor = fillColor
        outline.contentTintColor = tint
        mark.isHidden = !live
        mark.contentTintColor = tint
        needsLayout = true
    }

    override func layout() {
        super.layout()
        mark.frame = NSRect(x: (bounds.width - 7) / 2, y: (bounds.height - 7) / 2 + 1.5, width: 7, height: 7)
    }
}

/// Arc's keyboard-focus ring: 2 pt systemYellow with black 6/6 dashes, inside the edge.
final class FocusRingLayer: CALayer {
    private let yellow = CAShapeLayer()
    private let dashes = CAShapeLayer()
    private var radius = CraMetrics.rowCorner

    convenience init(radius: CGFloat) {
        self.init()
        self.radius = radius
    }

    override init() {
        super.init()
        for l in [yellow, dashes] {
            l.fillColor = nil
            l.lineWidth = 2
            addSublayer(l)
        }
        yellow.strokeColor = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1).cgColor
        dashes.strokeColor = NSColor.black.withAlphaComponent(0.92).cgColor
        dashes.lineDashPattern = [6, 6]
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSublayers() {
        super.layoutSublayers()
        let path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil)
        for l in [yellow, dashes] {
            l.frame = bounds
            l.path = path
        }
    }
}

/// What a drag over the list does to one row (SidebarDropPreview).
struct DropDecor: Equatable {
    var dimmed = false
    var nudge: CGFloat = 0
    /// "Move to Folder" / "Add to Split" on a folder or split the drop goes into.
    var badge: Badge?
    /// The row turns into what the drop makes.
    var combine: CombineDropPreview.Kind?
    var combineDragged: UUID?

    struct Badge: Equatable {
        let symbol: String
        let label: String
    }
}

// MARK: - Row base

@MainActor
class SidebarRowView: NSView {
    weak var list: SpaceListView?
    let key: SpaceListView.RowKey
    var colors: SidebarColors
    var isHovered = false { didSet { if isHovered != oldValue { hoverChanged() } } }
    private(set) var decor = DropDecor()
    private var badgeView: DropBadgeView?
    private var combineView: NSView?
    private var press: (event: NSEvent, point: NSPoint)?
    /// The hover/selection fill. Arc 1.170 draws it 36 pt tall on the 41 pt row pitch, so two
    /// filled rows keep a 5 pt gap (GitHub #10: Cra filled all 40 pt and rows touched).
    private let fillLayer = CALayer()
    static let fillInset: CGFloat = 2
    var fillRect: CGRect { bounds.insetBy(dx: 0, dy: Self.fillInset) }

    init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        self.key = key
        self.list = list
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = CraMetrics.rowCorner
        layer?.cornerCurve = .continuous
        fillLayer.cornerRadius = CraMetrics.rowCorner
        fillLayer.cornerCurve = .continuous
        // Changes show at once, as the view's own layer background did.
        fillLayer.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.insertSublayer(fillLayer, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func hoverChanged() { refreshBackground() }
    /// The row's resting fill (hover, selection).
    func baseFill() -> NSColor { .clear }
    /// Pointer moved within a hovered row (split rows track which pane it is over).
    func hoverMoved(to point: NSPoint) {}
    /// The item a press at `point` drags; nil when the row can't be dragged.
    func dragItemID(at point: NSPoint) -> UUID? { nil }
    func click(_ event: NSEvent, at point: NSPoint) {}
    func contextMenu(at point: NSPoint) -> NSMenu? { nil }
    /// The tooltip owner under the pointer.
    func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { nil }
    func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        colors = c
        refreshBackground()
    }

    func refreshBackground() {
        var fill = baseFill()
        if decor.combine != nil { fill = .clear } else if decor.badge != nil, fill == .clear { fill = colors.selectedFill }
        fillLayer.backgroundColor = fill.cgColor
    }

    override func layout() {
        super.layout()
        fillLayer.frame = fillRect
    }

    func applyDecor(_ d: DropDecor, animated: Bool) {
        guard d != decor else { return }
        let old = decor
        decor = d
        let alpha: CGFloat = d.combine != nil ? 0 : (d.dimmed ? 0.4 : 1)
        for v in subviews where v !== combineView { animated ? (v.animator().alphaValue = alpha) : (v.alphaValue = alpha) }
        if let badge = d.badge {
            let v = badgeView ?? DropBadgeView()
            if badgeView == nil {
                badgeView = v
                v.frame = fillRect
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            v.show(badge, colors: colors)
            v.alphaValue = alpha
        } else if let v = badgeView {
            badgeView = nil
            v.removeFromSuperview()
        }
        if d.combine != old.combine || d.combineDragged != old.combineDragged {
            combineView?.removeFromSuperview()
            combineView = nil
            if let kind = d.combine, let dragged = d.combineDragged, let list, let target = list.store.item(itemIDForCombine),
               let draggedItem = list.store.item(dragged) {
                let depth = list.depth(of: key)
                let host = CombineDropPreview(kind: kind, target: target, dragged: draggedItem, depth: depth,
                                              palette: list.palette, favicons: list.favicons)
                host.frame = bounds
                host.autoresizingMask = [.width, .height]
                addSubview(host)
                combineView = host
            }
        }
        refreshBackground()
    }

    /// The item a combine preview draws as the drop's target.
    var itemIDForCombine: UUID { if case .item(let id) = key { return id }; return UUID() }

    // Clicks act on release (SwiftUI's tap); a press that moves 3 pt starts the row's drag.
    override func mouseDown(with event: NSEvent) {
        press = (event, convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = press else { return }
        let q = convert(event.locationInWindow, from: nil)
        guard hypot(q.x - p.point.x, q.y - p.point.y) > 3 else { return }
        press = nil
        if let id = dragItemID(at: p.point) { list?.beginDrag(id, from: self, event: p.event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let p = press else { return }
        press = nil
        click(event, at: p.point)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu(at: convert(event.locationInWindow, from: nil))
    }
}

/// The badge a folder or split shows while a drop would go into it.
private final class DropBadgeView: NSView {
    private let pill = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 11, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = CraMetrics.rowCorner
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.shadow = NSShadow()
        pill.layer?.shadowOpacity = 0.08
        pill.layer?.shadowRadius = 2
        pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(pill)
        pill.addSubview(icon)
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ badge: DropDecor.Badge, colors: SidebarColors) {
        layer?.borderColor = colors.textPrimary.withAlphaComponent(0.3).cgColor
        pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(colors.isDark ? 0.14 : 0.9).cgColor
        icon.image = SidebarSymbols.image(badge.symbol, size: 10, weight: .semibold)
        icon.contentTintColor = colors.textPrimary
        label.stringValue = badge.label
        label.textColor = colors.textPrimary
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let ls = label.intrinsicContentSize
        let w = 8 + 12 + 4 + ls.width + 8
        pill.frame = NSRect(x: bounds.width - 8 - w, y: (bounds.height - 22) / 2, width: w, height: 22)
        icon.frame = NSRect(x: 8, y: 5, width: 12, height: 12)
        label.frame = NSRect(x: 24, y: (22 - ls.height) / 2, width: ls.width, height: ls.height)
    }
}

// MARK: - Tab row

struct TabRowModel: Equatable {
    var id: UUID
    var depth: Int
    var pinned: Bool
    var title: String
    var customTitle: Bool
    var renameText: String
    var subtitle: String?
    var icon: NSImage?
    var flipIcon: Bool
    var githubMark: Bool
    var editing: Bool
    var selected: Bool
    var highlighted: Bool
    var capturing: Bool
    var audible: Bool
    var muted: Bool
    var unread: Bool
    var navigatedAway: Bool
    var closeGroup: Int
    var focusRing: Bool
}

final class TabRowView: SidebarRowView, ArcTooltipTarget, NSTextFieldDelegate {
    private(set) var model: TabRowModel?
    private let favicon = SidebarFaviconView()
    private let titleLabel = NSTextField.sidebarLabel(size: 14)
    private let subtitleLabel = NSTextField.sidebarLabel(size: 11)
    private var renameField: NSTextField?
    private var accessories: [NSView] = []
    private var focusRing: FocusRingLayer?

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(favicon)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ m: TabRowModel) {
        guard m != model else { return }
        model = m
        if m.githubMark { favicon.showGitHubMark(colors: colors) } else { favicon.show(m.icon, flip: m.flipIcon, colors: colors) }
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        subtitleLabel.stringValue = m.subtitle ?? ""
        subtitleLabel.textColor = colors.textTertiary
        subtitleLabel.isHidden = m.subtitle == nil
        setAccessibilityLabel(m.title)
        if m.editing != (renameField != nil) { m.editing ? beginRename(m.renameText) : endRename() }
        if m.focusRing != (focusRing != nil) {
            if m.focusRing {
                let r = FocusRingLayer()
                r.frame = bounds
                r.zPosition = 10
                layer?.addSublayer(r)
                focusRing = r
            } else {
                focusRing?.removeFromSuperlayer()
                focusRing = nil
            }
        }
        rebuildAccessories()
        refreshBackground()
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override func baseFill() -> NSColor {
        guard let m = model else { return .clear }
        return m.highlighted ? colors.selectedFill : (isHovered ? colors.hoverFill : .clear)
    }

    override func refreshBackground() {
        super.refreshBackground()
        let lifted = model?.highlighted == true && !colors.isDark && decor.combine == nil
        layer?.shadowOpacity = lifted ? 0.06 : 0
        if lifted {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowRadius = 3
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowPath = CGPath(roundedRect: fillRect, cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        }
    }

    override func hoverChanged() {
        super.hoverChanged()
        rebuildAccessories()
    }

    /// Recording dot, mute or playing sound, unread dot, and on hover "back to pinned page" and close. Made once
    /// per row and shown or hidden: hover moves from row to row on every frame of a scroll.
    private lazy var captureDot: NSView = {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        let c = CALayer()
        c.frame = CGRect(x: 4.5, y: 4.5, width: 7, height: 7)
        c.cornerRadius = 3.5
        c.backgroundColor = NSColor.systemRed.cgColor
        dot.wantsLayer = true
        dot.layer?.addSublayer(c)
        _ = ArcTooltipAnchorView.attach(to: dot, help: "This tab is using your camera or microphone")
        return dot
    }()
    /// Arc 1.171: a playing or muted tab shows a speaker between the favicon and the title (17.5 pt
    /// wide, 8 pt before the title, in the glyph tone); clicking it mutes or unmutes the tab
    /// (31 Oct 2026, issue #28).
    private lazy var soundButton = SidebarGlyphButton(symbol: Self.soundSymbol, size: 20, iconSize: 13, weight: .regular,
                                                     help: "Mute Tab", colors: colors) { [weak self] in
        guard let self, let m = self.model, let list = self.list else { return }
        list.store.setMuted(m.id, !m.muted)
        list.actions.performAction("muteTab:\(m.id)")
    }
    private static let soundSymbol = "speaker.wave.3"
    private static let soundGlyphWidth: CGFloat = 17.5
    private var showsSound = false
    private lazy var unreadDot: NSView = {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        return dot
    }()
    private lazy var resetButton = SidebarGlyphButton(symbol: "arrow.uturn.backward", size: 22, iconSize: 13, help: "Back to pinned page", colors: colors) { [weak self] in
        guard let self, let id = self.model?.id else { return }
        self.list?.actions.resetPinnedTab(id)
    }
    private lazy var closeButton: SidebarGlyphButton = {
        let b = SidebarGlyphButton(symbol: "xmark", size: Self.closeSize, iconSize: 13, help: "", colors: colors) {}
        b.setCloseMark(minus: false, help: "")
        return b
    }()
    private static let closeSize: CGFloat = 22
    private var closeKind = ""

    private func rebuildAccessories() {
        guard let m = model, list != nil else { return }
        let id = m.id
        var shown: [NSView] = []
        if m.capturing { shown.append(captureDot) }
        let sound = (m.muted || m.audible) && !m.editing
        if sound {
            if soundButton.superview == nil { addSubview(soundButton) }
            soundButton.colors = colors
            soundButton.setSymbol(m.muted ? "speaker.slash" : Self.soundSymbol, iconSize: 13, weight: .regular,
                                  help: m.muted ? "Unmute Tab" : "Mute Tab")
        }
        soundButton.isHidden = !sound
        if sound != showsSound { showsSound = sound; needsLayout = true }
        if m.unread && !m.selected && !isHovered {
            unreadDot.layer?.backgroundColor = colors.textPrimary.withAlphaComponent(0.55).cgColor
            shown.append(unreadDot)
        }
        if isHovered && !m.editing {
            if m.navigatedAway { resetButton.colors = colors; shown.append(resetButton) }
            // Arc: the open pinned tab shows a minus (it unloads and stays pinned); any other pinned
            // tab an ✕ that archives it out of the pinned section; Today tabs an ✕ that archives.
            let kind = m.closeGroup > 1 ? "group\(m.closeGroup)" : (m.pinned && m.selected ? "keep" : (m.pinned ? "archivePinned" : "archive"))
            if kind != closeKind {
                closeKind = kind
                switch kind {
                case "keep":
                    closeButton.setCloseMark(minus: true, help: "Close and Keep Pinned (⌘W)")
                    closeButton.action = { [weak self] in self?.list?.closeTabs([id]) }
                case "archivePinned":
                    closeButton.setCloseMark(minus: false, help: "Archive this tab")
                    closeButton.action = { [weak self] in self?.list?.store.archiveTab(id, reason: .manual) }
                default:
                    closeButton.setCloseMark(minus: false, help: m.closeGroup > 1 ? "Close \(m.closeGroup) Tabs (⌘W)" : "Archive (⌘W)")
                    closeButton.action = { [weak self] in
                        guard let list = self?.list else { return }
                        list.closeTabs(list.closeGroup(for: id))
                    }
                }
            }
            closeButton.colors = colors
            shown.append(closeButton)
        }
        guard shown.map(ObjectIdentifier.init) != accessories.map(ObjectIdentifier.init) else { return }
        for v in accessories where !shown.contains(where: { $0 === v }) { v.isHidden = true }
        for v in shown {
            if v.superview == nil { addSubview(v) }
            v.isHidden = false
        }
        accessories = shown
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let h = bounds.height
        var x = 8 + CGFloat(m.depth) * CraMetrics.indent
        favicon.frame = NSRect(x: x, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        x += CraMetrics.favicon + 11
        if showsSound {
            let s = soundButton.size
            soundButton.frame = NSRect(x: x - (s.width - Self.soundGlyphWidth) / 2, y: (h - s.height) / 2, width: s.width, height: s.height)
            x += Self.soundGlyphWidth + 8
        }
        // HStack(spacing: 11) with a Spacer(minLength: 4) between the text and the trailing items.
        var right = bounds.width - 6
        for v in accessories.reversed() {
            // The unread dot is centred where the close button shows on hover, which is also
            // under a live folder's refresh button (FolderRowView, Arc lines them up too).
            let s = v.frame.size
            let slot = v === unreadDot ? Self.closeSize : s.width
            v.frame = NSRect(x: right - slot / 2 - s.width / 2, y: (h - s.height) / 2, width: s.width, height: s.height)
            right = v.frame.minX - 11
        }
        let textWidth = max(0, right - 4 - 11 - x)
        let th = titleLabel.intrinsicContentSize.height
        if m.subtitle != nil {
            let sh = subtitleLabel.intrinsicContentSize.height
            let top = (h - th - 1 - sh) / 2
            titleLabel.frame = NSRect(x: x - SidebarText.inset, y: top, width: textWidth + 2 * SidebarText.inset, height: th)
            subtitleLabel.frame = NSRect(x: x - SidebarText.inset, y: top + th + 1, width: textWidth + 2 * SidebarText.inset, height: sh)
        } else {
            titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: textWidth + 2 * SidebarText.inset, height: th)
        }
        if let f = renameField {
            let fh = f.intrinsicContentSize.height
            f.frame = NSRect(x: x - SidebarText.inset, y: (h - fh) / 2, width: max(0, bounds.width - 6 - x + SidebarText.inset), height: fh)
        }
        focusRing?.frame = fillRect
        if layer?.shadowOpacity ?? 0 > 0 {
            layer?.shadowPath = CGPath(roundedRect: fillRect, cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        }
    }

    // MARK: Rename

    private func beginRename(_ text: String) {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 14)
        f.textColor = colors.textPrimary
        f.delegate = self
        f.cell?.isScrollable = true
        renameField = f
        addSubview(f)
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
        needsLayout = true
        DispatchQueue.main.async { [weak self, weak f] in
            guard let f, let w = self?.window else { return }
            w.makeFirstResponder(f)
        }
    }

    private func endRename() {
        guard let f = renameField else { return }
        renameField = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        titleLabel.isHidden = false
        subtitleLabel.isHidden = model?.subtitle == nil
    }

    private func commitRename() {
        guard let m = model, let list, list.ui.renamingID == m.id, let f = renameField else { return }
        list.store.rename(m.id, to: f.stringValue)
        list.ui.renamingID = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { list?.ui.renamingID = nil; return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }

    // MARK: Events

    override func dragItemID(at point: NSPoint) -> UUID? { model?.editing == true ? nil : model?.id }

    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let m = model, let list else { return }
        // A click on the row (not the field) ends a rename, so it can never get stuck.
        if m.editing { commitRename() }
        list.clickTab(m.id, event: event)
    }

    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list else { return nil }
        return SidebarMenus.tab(m, list: list)
    }

    override func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { self }

    // ArcTooltipTarget: the title by the pointer; like Arc (didShowRenameHint),
    // "Double-click to rename" rides along once.
    var text: String { model.map { $0.editing ? "" : $0.title } ?? "" }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? {
        UserDefaults.standard.bool(forKey: "didShowRenameHint") || model?.customTitle != false ? nil : "Double-click to rename"
    }
    var optionText: String? { nil }
    var onShow: (() -> Void)? {
        { [weak self] in
            if self?.model?.customTitle == false { UserDefaults.standard.set(true, forKey: "didShowRenameHint") }
        }
    }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

// MARK: - Folder row

struct FolderRowModel: Equatable {
    var id: UUID
    var depth: Int
    var title: String
    var renameText: String
    var editing: Bool
    var expanded: Bool
    var live: Bool
    var tint: NSColor
    var fill: NSColor
    var tabCount: Int
    var liveBusy: Bool
    /// The warning button's tip after a failed refresh.
    var liveError: String?
    /// Where the warning button signs in, when GitHub asked for that (else it tries again).
    var liveSignInURL: String?
    var liveHelp: String
}

final class FolderRowView: SidebarRowView, NSTextFieldDelegate {
    private(set) var model: FolderRowModel?
    private let glyph = FolderGlyphView(frame: NSRect(x: 0, y: 0, width: CraMetrics.favicon, height: 20))
    private let titleLabel = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private var renameField: NSTextField?
    private var accessory: NSView?

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(glyph)
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ m: FolderRowModel) {
        guard m != model else { return }
        model = m
        glyph.show(expanded: m.expanded, live: m.live, tint: m.tint, fillColor: m.fill)
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        setAccessibilityLabel(m.title)
        if m.editing != (renameField != nil) { m.editing ? beginRename(m.renameText) : endRename() }
        rebuildAccessory()
        refreshBackground()
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override func baseFill() -> NSColor { isHovered ? colors.hoverFill : .clear }

    override func hoverChanged() {
        super.hoverChanged()
        rebuildAccessory()
    }

    /// A live folder's refresh button (spinner while it runs, warning after a failure);
    /// a closed folder's tab count on hover.
    private func rebuildAccessory() {
        accessory?.removeFromSuperview()
        accessory = nil
        guard let m = model, let list else { return }
        let id = m.id
        let hover = isHovered && !m.editing
        if m.live {
            if m.liveBusy {
                // A spinner fills its frame: the glyph's size, centred where the refresh button sits.
                let slot = NSView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
                let p = NSProgressIndicator(frame: NSRect(x: 7, y: 7, width: 12, height: 12))
                p.style = .spinning
                p.controlSize = .mini
                p.isIndeterminate = true
                p.startAnimation(nil)
                slot.addSubview(p)
                accessory = slot
            } else if let error = m.liveError {
                // Arc keeps the warning on hover too ("Sign back in to GitHub."): a click signs in, or tries again.
                let signIn = m.liveSignInURL
                accessory = SidebarGlyphButton(symbol: "exclamationmark.triangle", size: 26, iconSize: 13, weight: .regular,
                                               help: error, colors: colors) { [weak list] in
                    if let signIn { list?.actions.openURL(signIn) } else { LiveFolderManager.shared.refresh(id) }
                }
            } else if hover {
                accessory = SidebarGlyphButton(symbol: "arrow.clockwise", size: 26, iconSize: 12, help: m.liveHelp, colors: colors) {
                    LiveFolderManager.shared.refresh(id)
                }
            }
        } else if hover && !m.expanded {
            let l = NSTextField.sidebarLabel(size: 11, weight: .medium)
            l.stringValue = "\(m.tabCount)"
            l.textColor = colors.textTertiary
            l.sizeToFit()
            accessory = l
        }
        _ = list
        if let a = accessory { addSubview(a) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let h = bounds.height
        var x = 8 + CGFloat(m.depth) * CraMetrics.indent
        glyph.frame = NSRect(x: x, y: (h - 20) / 2, width: CraMetrics.favicon, height: 20)
        x += CraMetrics.favicon + 11
        var right = bounds.width
        if let a = accessory {
            let s = a.frame.size
            // A live folder's button is centred over its tabs' unread dots and close buttons (17 pt in).
            right -= (m.live ? 4 : 8) + s.width
            a.frame = NSRect(x: right, y: (h - s.height) / 2, width: s.width, height: s.height)
            right -= 11
        }
        let th = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, right - 8 - 11 - x) + 2 * SidebarText.inset, height: th)
        if let f = renameField {
            let fh = f.intrinsicContentSize.height
            f.frame = NSRect(x: x - SidebarText.inset, y: (h - fh) / 2, width: max(0, bounds.width - 8 - x + SidebarText.inset), height: fh)
        }
    }

    private func beginRename(_ text: String) {
        let f = NSTextField(string: text)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 14, weight: .medium)
        f.textColor = colors.textPrimary
        f.delegate = self
        f.cell?.isScrollable = true
        renameField = f
        addSubview(f)
        titleLabel.isHidden = true
        needsLayout = true
        DispatchQueue.main.async { [weak self, weak f] in
            guard let f, let w = self?.window else { return }
            w.makeFirstResponder(f)
        }
    }

    private func endRename() {
        guard let f = renameField else { return }
        renameField = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        titleLabel.isHidden = false
    }

    private func commitRename() {
        guard let m = model, let list, list.ui.renamingID == m.id, let f = renameField else { return }
        list.store.rename(m.id, to: f.stringValue.isEmpty ? "Folder" : f.stringValue)
        list.ui.renamingID = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { list?.ui.renamingID = nil; return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }

    override func dragItemID(at point: NSPoint) -> UUID? { model?.editing == true ? nil : model?.id }

    // Every click toggles, however fast they come: double-click-to-rename made quick
    // open/close clicks start a rename that then swallowed the clicks. Rename is in the menu.
    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let m = model, let list else { return }
        if m.editing { commitRename() }
        list.store.setExpanded(m.id, !m.expanded)
    }

    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list, let item = list.store.item(m.id) else { return nil }
        return item.isLiveFolder ? SidebarMenus.liveFolder(item, list: list) : SidebarMenus.folder(item, list: list)
    }
}

// MARK: - Split row

struct SplitRowModel: Equatable {
    struct Cell: Equatable {
        var id: UUID
        var title: String
        var icon: NSImage?
        var flipIcon: Bool
    }
    var id: UUID
    var depth: Int
    var today: Bool
    var selected: Bool
    var focusRing: Bool
    var cells: [Cell]
}

/// Arc's split cell (SplitViewCellView): the panes side by side, hairlines between them.
final class SplitRowView: SidebarRowView {
    private(set) var model: SplitRowModel?
    private var cells: [SplitCellView] = []
    private var separators: [NSView] = []
    private var focusRing: FocusRingLayer?

    func apply(_ m: SplitRowModel) {
        guard m != model else { return }
        let closeChanged = m.selected != model?.selected || m.today != model?.today
        model = m
        defer { if closeChanged { for c in cells where c.hovering { c.refreshClose() } } }
        if cells.map(\.cellID) != m.cells.map(\.id) {
            cells.forEach { $0.removeFromSuperview() }
            separators.forEach { $0.removeFromSuperview() }
            cells = m.cells.map { SplitCellView(cellID: $0.id, row: self) }
            separators = (0..<max(0, m.cells.count - 1)).map { _ in
                let v = NSView()
                v.wantsLayer = true
                return v
            }
            cells.forEach { addSubview($0) }
            separators.forEach { addSubview($0) }
        }
        for (c, cm) in zip(cells, m.cells) { c.apply(cm, colors: colors) }
        for s in separators { s.layer?.backgroundColor = colors.separator.cgColor }
        if m.focusRing != (focusRing != nil) {
            if m.focusRing {
                let r = FocusRingLayer()
                r.zPosition = 10
                layer?.addSublayer(r)
                focusRing = r
            } else {
                focusRing?.removeFromSuperlayer()
                focusRing = nil
            }
        }
        refreshBackground()
        needsLayout = true
    }

    override func setColors(_ c: SidebarColors) {
        guard c != colors else { return }
        super.setColors(c)
        if let m = model { model = nil; apply(m) }
    }

    override func baseFill() -> NSColor {
        guard let m = model else { return .clear }
        return m.selected ? colors.selectedFill : (isHovered ? colors.hoverFill : .clear)
    }

    override func refreshBackground() {
        super.refreshBackground()
        let lifted = model?.selected == true && !colors.isDark && decor.combine == nil
        layer?.shadowOpacity = lifted ? 0.06 : 0
        if lifted {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowRadius = 3
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowPath = CGPath(roundedRect: fillRect, cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        }
    }

    override func hoverChanged() {
        super.hoverChanged()
        if !isHovered { cells.forEach { $0.hovering = false } }
    }

    override func hoverMoved(to point: NSPoint) {
        for c in cells { c.hovering = c.frame.contains(point) }
    }

    override func layout() {
        super.layout()
        guard let m = model, !cells.isEmpty else { return }
        let x0 = CGFloat(m.depth) * CraMetrics.indent
        let n = CGFloat(cells.count)
        let w = (bounds.width - x0 - (n - 1)) / n
        var x = x0
        for (i, c) in cells.enumerated() {
            if i > 0 {
                separators[i - 1].frame = NSRect(x: x, y: SplitRowMetrics.separatorInset, width: 1, height: bounds.height - 2 * SplitRowMetrics.separatorInset)
                x += 1
            }
            c.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w
        }
        focusRing?.frame = fillRect
    }

    private func cell(at point: NSPoint) -> SplitCellView? { cells.first { $0.frame.contains(point) } }

    // The split moves as one (into Pinned, a folder, another space); a pane leaves it through
    // the menu or ⌥ on its close button, as in Arc.
    override func dragItemID(at point: NSPoint) -> UUID? { model?.id }

    override func click(_ event: NSEvent, at point: NSPoint) {
        guard let c = cell(at: point), let list else { return }
        list.store.selectTab(c.cellID, window: list.ui.windowID)
    }

    // Arc shows the split's menu over any pane; each pane's own items are a submenu in it.
    override func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let m = model, let list else { return nil }
        return SidebarMenus.split(m, list: list)
    }

    override func tooltipTarget(at point: NSPoint) -> (any ArcTooltipTarget)? { cell(at: point) }
}

enum SplitRowMetrics {
    static let separatorInset: CGFloat = 9
}

/// One pane inside the split row (Arc: SplitViewCellChildItemView).
final class SplitCellView: NSView, ArcTooltipTarget {
    let cellID: UUID
    private weak var row: SplitRowView?
    private let favicon = SidebarFaviconView()
    private let titleLabel = NSTextField.sidebarLabel(size: 14)
    private var close: SidebarGlyphButton?
    private var title = ""
    var hovering = false { didSet { if hovering != oldValue { refreshClose() } } }

    init(cellID: UUID, row: SplitRowView) {
        self.cellID = cellID
        self.row = row
        super.init(frame: .zero)
        addSubview(favicon)
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    // Presses go to the row, which knows which pane they are on; the close button keeps its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let close, close.frame.contains(convert(point, from: superview)) { return close }
        return nil
    }

    func apply(_ m: SplitRowModel.Cell, colors: SidebarColors) {
        title = m.title
        favicon.show(m.icon, flip: m.flipIcon, colors: colors)
        titleLabel.stringValue = m.title
        titleLabel.textColor = colors.textPrimary
        close?.colors = colors
        needsLayout = true
    }

    func refreshClose() {
        close?.removeFromSuperview()
        close = nil
        guard hovering, let row, let list = row.list else { needsLayout = true; return }
        let id = cellID
        // Arc 1.171: an open pinned split shows a minus (the whole split closes and stays pinned),
        // like an open pinned tab; otherwise the ✕ takes this pane out.
        let keep = row.model.map { !$0.today && $0.selected } ?? false
        let b = SidebarGlyphButton(symbol: "xmark", size: 20, iconSize: 11, help: keep ? "Close and Keep Pinned (⌘W)" : "Close pane",
                                   optionHelp: "Separate from Split View", colors: row.colors) { [weak list] in
            // Option-click un-splits instead of closing (Arc flag option-click-split-tab-close-button-to-unsplit).
            if NSEvent.modifierFlags.contains(.option) { list?.store.separateFromSplit(id) } else if keep { list?.actions.closeTab(id) } else { list?.actions.closePane(id) }
        }
        if keep { b.setCloseMark(minus: true, help: "Close and Keep Pinned (⌘W)") }
        addSubview(b)
        close = b
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        favicon.frame = NSRect(x: 8, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        var right = bounds.width - 4
        if let close {
            right -= 20
            close.frame = NSRect(x: right, y: (h - 20) / 2, width: 20, height: 20)
            right -= 8
        }
        let th = titleLabel.intrinsicContentSize.height
        let x = 8 + CraMetrics.favicon + 8
        titleLabel.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, right - 2 - 8 - x) + 2 * SidebarText.inset, height: th)
    }

    var text: String { title }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

// MARK: - Small rows

struct LiveStatusModel: Equatable {
    var text: String
    var url: String?
    var depth: Int
}

/// A line inside an open live folder with nothing to show, or when GitHub can't be read.
final class LiveStatusRowView: SidebarRowView {
    private(set) var model: LiveStatusModel?
    private let label: NSTextField = {
        let l = NSTextField(wrappingLabelWithString: "")
        l.font = .systemFont(ofSize: 12)
        l.maximumNumberOfLines = 3
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func leading(depth: Int) -> CGFloat { 8 + CGFloat(depth) * CraMetrics.indent + CraMetrics.favicon + 11 }

    static func height(_ m: LiveStatusModel, width: CGFloat) -> CGFloat {
        let w = max(1, width - leading(depth: m.depth) - 10)
        let font = NSFont.systemFont(ofSize: 12)
        let line = ceil(font.ascender - font.descender + font.leading)
        let r = (m.text as NSString).boundingRect(with: NSSize(width: w, height: line * 3), options: [.usesLineFragmentOrigin],
                                                  attributes: [.font: font])
        return ceil(min(r.height, line * 3)) + 16
    }

    func apply(_ m: LiveStatusModel) {
        guard m != model else { return }
        model = m
        label.stringValue = m.text
        refreshColors()
        needsLayout = true
    }

    private func refreshColors() {
        label.textColor = model?.url != nil && isHovered ? colors.textSecondary : colors.textTertiary
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refreshColors()
    }

    override func baseFill() -> NSColor { model?.url != nil && isHovered ? colors.hoverFill : .clear }

    override func hoverChanged() {
        super.hoverChanged()
        refreshColors()
    }

    override func layout() {
        super.layout()
        guard let m = model else { return }
        let x = Self.leading(depth: m.depth)
        label.frame = NSRect(x: x - SidebarText.inset, y: 8, width: max(0, bounds.width - x - 10) + 2 * SidebarText.inset, height: max(0, bounds.height - 16))
    }

    override func click(_ event: NSEvent, at point: NSPoint) {
        if let url = model?.url { list?.actions.openURL(url) }
    }
}

final class NewTabRowView: SidebarRowView {
    private let plus = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 14)

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        // Arc's plus, fitted pixel by pixel at 1x and 2x.
        plus.image = SidebarSymbols.image("plus", size: 14.5, weight: .medium)
        plus.imageScaling = .scaleNone
        label.stringValue = "New Tab"
        addSubview(plus)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("New Tab")
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshColors() {
        let c = isHovered ? colors.textPrimary : colors.textSecondary
        plus.contentTintColor = c
        label.textColor = c
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refreshColors()
    }

    override func baseFill() -> NSColor { isHovered ? colors.selectedFill : .clear }

    override func hoverChanged() {
        super.hoverChanged()
        refreshColors()
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        plus.frame = NSRect(x: 8, y: 0, width: CraMetrics.favicon, height: h)
        let th = label.intrinsicContentSize.height
        let x = 8 + CraMetrics.favicon + 9
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, bounds.width - 10 - x) + 2 * SidebarText.inset, height: th)
    }

    override func click(_ event: NSEvent, at point: NSPoint) { list?.actions.openCommandBar(.newTab) }
}

/// The line between pinned and Today; "Clear" shows on hover.
final class DividerRowView: SidebarRowView {
    private let line = NSView()
    private var clear: ClearButton?
    private var hasToday = false

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        line.wantsLayer = true
        addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event) }

    func apply(hasToday: Bool) {
        self.hasToday = hasToday
        refresh()
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refresh()
    }

    override func hoverChanged() { refresh() }

    private func refresh() {
        line.layer?.backgroundColor = colors.separator.cgColor
        line.alphaValue = hasToday ? 1 : 0
        let show = isHovered && hasToday
        if show, clear == nil, let list {
            let b = ClearButton(colors: colors) { [weak list] in
                guard let list else { return }
                list.store.clearToday(list.spaceID)
            }
            b.alphaValue = 0
            addSubview(b)
            clear = b
            b.animator().alphaValue = 1
        } else if !show, let b = clear {
            clear = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                b.animator().alphaValue = 0
            } completionHandler: { b.removeFromSuperview() }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var right = bounds.width - 20
        if let clear {
            let s = clear.fittingSize
            clear.frame = NSRect(x: right - s.width, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
            right -= s.width + 8
        }
        line.frame = NSRect(x: 20, y: (bounds.height - 1) / 2, width: max(0, right - 20), height: 1)
    }

    private final class ClearButton: NSView {
        private let label = NSTextField.sidebarLabel(size: 11, weight: .semibold)
        private let action: () -> Void

        init(colors: SidebarColors, action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            label.stringValue = "Clear"
            label.textColor = colors.textSecondary
            label.sizeToFit()
            addSubview(label)
            frame.size = label.frame.size
            _ = ArcTooltipAnchorView.attach(to: self, help: "Clear Today tabs")
        }

        required init?(coder: NSCoder) { fatalError() }

        override var fittingSize: NSSize { label.frame.size }
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
        }
    }
}

/// "Drop to Pin": an empty pinned list opens a target while a drag is on.
final class PinPlaceholderRowView: SidebarRowView {
    private let border = CAShapeLayer()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 12, weight: .medium)
    private var active = false

    override init(key: SpaceListView.RowKey, list: SpaceListView, colors: SidebarColors) {
        super.init(key: key, list: list, colors: colors)
        border.fillColor = nil
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer?.addSublayer(border)
        icon.image = SidebarSymbols.image("pin", size: 11, weight: .semibold)
        icon.imageScaling = .scaleNone
        label.stringValue = "Drop to Pin"
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(active: Bool) {
        self.active = active
        refresh()
    }

    override func setColors(_ c: SidebarColors) {
        super.setColors(c)
        refresh()
    }

    override func baseFill() -> NSColor { active ? colors.hoverFill : .clear }

    private func refresh() {
        border.strokeColor = colors.textTertiary.withAlphaComponent(active ? 0.6 : 0.3).cgColor
        icon.contentTintColor = colors.textSecondary
        label.textColor = colors.textSecondary
        refreshBackground()
    }

    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: CraMetrics.rowCorner, cornerHeight: CraMetrics.rowCorner, transform: nil)
        let ls = label.intrinsicContentSize
        let w = 14 + 6 + ls.width
        let x = (bounds.width - w) / 2
        icon.frame = NSRect(x: x, y: 0, width: 14, height: bounds.height)
        label.frame = NSRect(x: x + 20, y: (bounds.height - ls.height) / 2, width: ls.width, height: ls.height)
    }
}
