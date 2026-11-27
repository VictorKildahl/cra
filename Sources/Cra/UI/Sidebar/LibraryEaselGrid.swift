import AppKit

/// Library ▸ Easels as Arc 1.172.1 lays it out (Victor's Arc, 8 Nov 2026, 2x stills): the media
/// grid's tiles, two to a row, each holding a light card (white 3 pt rim, 8 pt corners) with the
/// easel drawn small on it and, at its bottom left, Arc's pink squiggle over the title in bold.
/// No day headers. Click opens the easel; right-click: Share Easel… (Cra's link, EaselShare), Delete.
struct EaselEntry: Equatable {
    var id: UUID
    var title: String
    var edited: Date
}

final class EaselRowCell: NSView {
    private var tiles: [EaselTile] = []
    var open: (EaselEntry) -> Void = { _ in }
    var share: (EaselEntry) -> Void = { _ in }
    var delete: (EaselEntry) -> Void = { _ in }

    override var isFlipped: Bool { true }

    func show(_ entries: [EaselEntry], ink: NSColor) {
        while tiles.count < 2 {
            let t = EaselTile()
            t.open = { [weak self] in self?.open($0) }
            t.share = { [weak self] in self?.share($0) }
            t.delete = { [weak self] in self?.delete($0) }
            tiles.append(t)
            addSubview(t)
        }
        for (i, t) in tiles.enumerated() {
            t.isHidden = i >= entries.count
            if i < entries.count { t.show(entries[i], ink: ink) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = MediaGridMetrics.self
        let w = m.tile(width: bounds.width)
        for (i, t) in tiles.enumerated() { t.frame = NSRect(x: m.inset + CGFloat(i) * (w + m.gap), y: 0, width: w, height: w) }
    }
}

final class EaselTile: NSView {
    var open: (EaselEntry) -> Void = { _ in }
    var share: (EaselEntry) -> Void = { _ in }
    var delete: (EaselEntry) -> Void = { _ in }
    private var entry: EaselEntry?
    private var ink: NSColor = .white
    private let card = CALayer()
    private let picture = CALayer()
    private let mark = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private var hovering = false { didSet { if hovering != oldValue { refresh(animated: true) } } }
    private var downAt: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        card.backgroundColor = NSColor(white: 0.957, alpha: 1).cgColor
        card.borderColor = NSColor.white.cgColor
        card.borderWidth = 3
        card.cornerRadius = 8
        card.cornerCurve = .continuous
        card.masksToBounds = true
        card.shadowColor = NSColor.black.cgColor
        layer?.addSublayer(card)
        picture.contentsGravity = .resizeAspect
        card.addSublayer(picture)
        // Arc's squiggle (its Easel mark), pink.
        mark.image = NSImage(systemSymbolName: "scribble", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .bold))
        mark.contentTintColor = NSColor(srgbRed: 0.88, green: 0.40, blue: 0.45, alpha: 1)
        addSubview(mark)
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = NSColor(white: 0.12, alpha: 1)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ e: EaselEntry, ink: NSColor) {
        self.ink = ink
        title.stringValue = e.title.isEmpty ? "Untitled Easel" : e.title
        setAccessibilityLabel(title.stringValue)
        if e != entry {
            entry = e
            picture.contents = EaselThumbnail.image(for: e.id, edited: e.edited)
        }
        refresh()
        needsLayout = true
    }

    /// Arc's tile under the pointer: its backing brightens and the tile grows about its centre
    /// (CraCore EaselTileHover), both in a tenth of a second; the same way back.
    private func refresh(animated: Bool = false) {
        guard let layer else { return }
        let fill = ink.withAlphaComponent(EaselTileHover.fill(hovering: hovering)).cgColor
        if animated {
            let tint = CABasicAnimation(keyPath: "backgroundColor")
            tint.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            tint.toValue = fill
            tint.duration = EaselTileHover.duration
            tint.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(tint, forKey: "hover_tint")
        }
        layer.backgroundColor = fill
        // AppKit owns a layer-backed view's anchor and transform, so the growth is an animation
        // that stays while the pointer is over the tile, carrying the centre itself.
        var to = CATransform3DIdentity
        if hovering {
            let s = EaselTileHover.scale, a = layer.anchorPoint
            let c = CGPoint(x: bounds.width * (0.5 - a.x), y: bounds.height * (0.5 - a.y))
            to = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(c.x, c.y, 0), s, s, 1), -c.x, -c.y, 0)
        }
        guard animated || !hovering else { return }
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
        grow.toValue = NSValue(caTransform3D: to)
        grow.duration = animated ? EaselTileHover.duration : 0
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = !hovering
        layer.add(grow, forKey: "hover_grow")
        // Over its neighbours while it is the larger one.
        layer.zPosition = hovering ? 1 : 0
    }

    /// cra://debug?easelTile=open|delete: a click on the tile (its Peek), or its menu's Delete.
    func debugPress(_ what: String) {
        guard let entry else { return }
        if what == "delete" { delete(entry) } else { open(entry) }
    }

    /// cra://debug?easelTileHover=1|0: the pointer over the tile, or gone; what it then shows.
    func debugHover(_ on: Bool, done: @escaping (String) -> Void) {
        hovering = on
        DispatchQueue.main.asyncAfter(deadline: .now() + EaselTileHover.duration + 0.15) { [weak self] in
            guard let self, let layer = self.layer else { return }
            let scale = (layer.presentation() ?? layer).transform.m11
            let fill = layer.backgroundColor.map { $0.alpha } ?? 0
            done(String(format: "hover=%@ scale=%.3f fill=%.2f title=%@", on ? "on" : "off", scale, fill, self.title.stringValue))
        }
    }

    override func layout() {
        super.layout()
        // Arc: the card 9 pt inside the tile; the title 9.5 pt in from the card, 12 pt off its bottom.
        let c = bounds.insetBy(dx: 9, dy: 9)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.frame = c
        // What's drawn sits above the squiggle and the title (52 pt at the card's bottom).
        picture.frame = NSRect(x: 10, y: 10, width: max(0, c.width - 20), height: max(0, c.height - 62))
        CATransaction.commit()
        let th: CGFloat = 17
        title.frame = NSRect(x: c.minX + 9.5 - 2, y: c.maxY - 12 - th, width: c.width - 19 + 4, height: th)
        mark.frame = NSRect(x: c.minX + 9, y: title.frame.minY - 20, width: 18, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }
    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, let entry, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        open(entry)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let entry else { return nil }
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Share Easel…") { [weak self] in self?.share(entry) }
        m.addItem(.separator())
        MenuItems.add(m, "Delete") { [weak self] in self?.delete(entry) }
        return m
    }
}

/// An easel drawn small for its Library card: what's on it, fitted in, dark on the light card.
@MainActor
enum EaselThumbnail {
    private static var cache: [UUID: (Date, NSImage)] = [:]

    static func image(for id: UUID, edited: Date) -> NSImage? {
        if let (d, img) = cache[id], d == edited { return img }
        let easel = EaselFiles.load(id)
        // A picture set as the easel's thumbnail stands for it on its own.
        let items = easel.thumbnailItem.map { [$0] } ?? easel.items
        guard !items.isEmpty else { cache[id] = (edited, NSImage()); return nil }
        let minX = items.map(\.frame.x).min()!, minY = items.map(\.frame.y).min()!
        let maxX = items.map { $0.frame.x + $0.frame.width }.max()!, maxY = items.map { $0.frame.y + $0.frame.height }.max()!
        let box = NSRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        let side: CGFloat = 220
        let scale = min(side / box.width, side / box.height, 1)
        let size = NSSize(width: max(1, box.width * scale), height: max(1, box.height * scale))
        let ink = NSColor(white: 0.2, alpha: 1)
        let image = NSImage(size: size, flipped: true) { _ in
            let t = NSAffineTransform()
            t.scale(by: scale)
            t.translateX(by: -box.minX, yBy: -box.minY)
            t.concat()
            for item in items {
                let r = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
                // The canvas's colours, in the palette's light look (black ink on the light card).
                let shade = item.shade ?? (item.color == nil ? Easel.defaultShade(item.kind) : nil)
                let color = shade.map { NSColor(hex: Easel.hex($0, palette: easel.palette, dark: false)) } ?? item.color.map { NSColor(hex: $0) } ?? ink
                color.setStroke()
                color.withAlphaComponent(Easel.shapeFillOpacity).setFill()
                switch item.kind {
                case .rectangle:
                    let p = NSBezierPath(rect: r); p.fill(); p.lineWidth = 3 / scale; p.stroke()
                case .ellipse:
                    let p = NSBezierPath(ovalIn: r); p.fill(); p.lineWidth = 3 / scale; p.stroke()
                case .arrow(let a, let b):
                    let p = NSBezierPath(); p.move(to: NSPoint(x: a.x, y: a.y)); p.line(to: NSPoint(x: b.x, y: b.y))
                    p.lineWidth = 3 / scale; p.stroke()
                case .freehand(let pts):
                    guard let first = pts.first else { continue }
                    let p = NSBezierPath(); p.move(to: NSPoint(x: first.x, y: first.y))
                    for q in pts.dropFirst() { p.line(to: NSPoint(x: q.x, y: q.y)) }
                    p.lineWidth = 3 / scale; p.lineCapStyle = .round; p.stroke()
                case .image(let file):
                    NSImage(contentsOf: EaselFiles.pictures(id).appendingPathComponent(file))?.draw(in: r)
                case .link(let l):
                    let card = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
                    NSColor.white.setFill(); card.fill()
                    if let file = l.image, let pic = NSImage(contentsOf: EaselFiles.pictures(id).appendingPathComponent(file)) {
                        NSGraphicsContext.saveGraphicsState(); card.addClip()
                        EaselCards.drawCovering(pic, in: NSRect(x: r.minX, y: r.minY, width: r.width, height: max(0, r.height - Easel.linkBarHeight)))
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    ink.setStroke(); card.lineWidth = 1 / scale; card.stroke()
                case .capture(let c):
                    NSImage(contentsOf: EaselFiles.pictures(id).appendingPathComponent(c.image))?.draw(in: r)
                case .text(let s, let size):
                    (s as NSString).draw(in: r, withAttributes: [.font: EaselSheetView.font(item.style, size: size, title: false), .foregroundColor: ink])
                }
            }
            return true
        }
        cache[id] = (edited, image)
        return image
    }
}
