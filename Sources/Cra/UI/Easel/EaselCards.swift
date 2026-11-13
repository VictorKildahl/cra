import AppKit

/// How Arc draws a link and a capture on an Easel (EaselLinkView, EaselWebCardView), in its dark
/// look (its export viewer's dark values: card black, border #686A6B, filler #686A6B, secondary text
/// at 50 %, the capture's hover bar #252832 with a 23 pt chip).
@MainActor
enum EaselCards {
    static let cardFill = NSColor.black
    static let cardBorder = NSColor(srgbRed: 0x68 / 255.0, green: 0x6A / 255.0, blue: 0x6B / 255.0, alpha: 1)
    static let filler = cardBorder
    static let secondary = NSColor(white: 1, alpha: 0.5)
    static let barFill = NSColor(srgbRed: 0x25 / 255.0, green: 0x28 / 255.0, blue: 0x32 / 255.0, alpha: 1)
    static let chipFill = NSColor(srgbRed: 246 / 255.0, green: 246 / 255.0, blue: 246 / 255.0, alpha: 0.11)

    // MARK: Link

    /// Arc 1.172.2's link card (EaselLinkView, measured 11 Nov 2026 at 2x): 10 pt corners and a
    /// 1.5 pt #686A6B border; the page's picture fills the top (cropped to fill), then a 59 pt black
    /// bar: the site's icon (26 pt, 17 pt in), the title (21 pt medium, #D8D8D8, one line) and a
    /// 36 pt ↗ chip (#1B1B1B, 8 pt corners) 17.5 pt from the right. A video gets ▶ over its picture.
    static func drawLink(_ link: Easel.Link, in r: NSRect, picture: NSImage?, favicon: NSImage?) {
        let card = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: 10, yRadius: 10)
        cardFill.setFill(); card.fill()
        let barHeight = min(CGFloat(Easel.linkBarHeight), r.height)
        let top = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - barHeight)
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        filler.setFill(); top.fill()
        if let picture { drawCovering(picture, in: top) }
        NSGraphicsContext.restoreGraphicsState()
        if Easel.isVideo(link.url), top.height > 60 {
            let disc = NSRect(x: top.midX - 28, y: top.midY - 28, width: 56, height: 56)
            NSColor(white: 0, alpha: 0.55).setFill(); NSBezierPath(ovalIn: disc).fill()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: disc.minX + 22, y: disc.minY + 16)); play.line(to: NSPoint(x: disc.minX + 22, y: disc.maxY - 16))
            play.line(to: NSPoint(x: disc.maxX - 16, y: disc.midY)); play.close()
            NSColor.white.setFill(); play.fill()
        }
        cardBorder.setStroke(); card.lineWidth = 1.5; card.stroke()

        let bar = NSRect(x: r.minX, y: r.maxY - barHeight, width: r.width, height: barHeight)
        var x = bar.minX + 17
        if let favicon {
            favicon.draw(in: NSRect(x: x, y: bar.midY - 13, width: 26, height: 26), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        x += 26 + 15
        let chip = NSRect(x: bar.maxX - 17.5 - 36, y: bar.midY - 18, width: 36, height: 36)
        NSColor(white: 0x1B / 255.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 8, yRadius: 8).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold).applying(.init(paletteColors: [NSColor(white: 0.55, alpha: 1)]))
        if let glyph = NSImage(systemSymbolName: "arrow.up.forward", accessibilityDescription: "Open")?.withSymbolConfiguration(config) {
            glyph.draw(in: NSRect(x: chip.midX - glyph.size.width / 2, y: chip.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 21, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0xD8 / 255.0, alpha: 1), .paragraphStyle: style]
        let h = ceil(font.ascender - font.descender)
        ((link.title ?? link.host) as NSString).draw(with: NSRect(x: x, y: bar.midY - h / 2, width: max(0, chip.minX - 12 - x), height: h),
                                                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    /// The ↗ chip of a link card at `r`.
    static func linkChipRect(in r: NSRect) -> NSRect {
        let barHeight = min(CGFloat(Easel.linkBarHeight), r.height)
        return NSRect(x: r.maxX - 17.5 - 36, y: r.maxY - barHeight / 2 - 18, width: 36, height: 36)
    }

    // MARK: Capture

    /// Arc's web card: the capture on a card with 10 pt corners and a 1 pt border; under the pointer
    /// a bar 6 pt in from the bottom (36 pt, 8 pt corners) with the site's icon, the page's title and
    /// an ↗ chip that opens the page.
    static func drawCapture(_ capture: Easel.Capture, in r: NSRect, picture: NSImage?, live: Bool, hovered: Bool, favicon: NSImage?) {
        let card = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        cardFill.setFill(); card.fill()
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        if let picture { drawFitting(picture, in: r) }
        NSGraphicsContext.restoreGraphicsState()
        cardBorder.setStroke(); card.lineWidth = 1; card.stroke()
        guard hovered, r.width > 80, r.height > 48 else { return }
        let bar = barRect(in: r)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.17)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 1.5
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        barFill.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        var x = bar.minX + 12
        if let favicon {
            favicon.draw(in: NSRect(x: x, y: bar.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += 22
        }
        let chip = chipRect(in: r)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let title = capture.title ?? Easel.Link(url: capture.url).host
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white, .paragraphStyle: style]
        let h: CGFloat = 18
        (title as NSString).draw(with: NSRect(x: x, y: bar.midY - h / 2, width: max(0, chip.minX - 6 - x), height: h),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        chipFill.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [NSColor(white: 1, alpha: 0.7)]))
        if let glyph = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Open")?.withSymbolConfiguration(config) {
            glyph.draw(in: NSRect(x: chip.midX - glyph.size.width / 2, y: chip.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
        }
        _ = live
    }

    static func barRect(in r: NSRect) -> NSRect { NSRect(x: r.minX + 6, y: r.maxY - 6 - 36, width: r.width - 12, height: 36) }
    /// The ↗ chip: 23 pt, 6 pt in from the bar's right end.
    static func chipRect(in r: NSRect) -> NSRect {
        let bar = barRect(in: r)
        return NSRect(x: bar.maxX - 6 - 23, y: bar.midY - 11.5, width: 23, height: 23)
    }

    // MARK: Pictures

    /// Fills `r`, cropping what sticks out (object-fit: cover).
    static func drawCovering(_ image: NSImage, in r: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let k = max(r.width / image.size.width, r.height / image.size.height)
        let size = NSSize(width: image.size.width * k, height: image.size.height * k)
        image.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Fits inside `r` (object-fit: contain).
    static func drawFitting(_ image: NSImage, in r: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let k = min(r.width / image.size.width, r.height / image.size.height)
        let size = NSSize(width: image.size.width * k, height: image.size.height * k)
        image.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Arc's colour picker over a picked shape (EaselUI ColorPickerView, measured 11 Nov 2026 at 2x): a
/// black panel 180 × 69 pt with 8 pt corners, centred over the shape with a small arrow down to it;
/// 20 pt dots 26 pt apart in two rows (Easel.pickerRows), the second half a step in; the shape's
/// colour has a white check mark; black has a dark grey ring so it shows on the panel.
@MainActor
final class EaselColorPicker: NSView {
    var palette: Easel.Palette?
    var current: Easel.Shade? { didSet { needsDisplay = true } }
    var onPick: (Easel.Shade) -> Void = { _ in }

    static let size = NSSize(width: 180, height: 75)  // the panel, 69 pt, and its 6 pt arrow
    static let panelHeight: CGFloat = 69
    static let dot: CGFloat = 20, pitch: CGFloat = 26

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Where the panel goes for a shape at `r`: centred above it, its arrow 7 pt off the shape.
    static func frame(over r: NSRect) -> NSRect {
        NSRect(x: r.midX - size.width / 2, y: r.minY - 7 - size.height, width: size.width, height: size.height)
    }

    func dotRect(row: Int, column: Int) -> NSRect {
        let count = CGFloat(Easel.pickerRows[0].count)
        let left = (bounds.width - (count - 1) * Self.pitch - Self.dot) / 2 + (row == 1 ? Self.pitch / 2 : 0)
        let cy: CGFloat = row == 0 ? 21 : 47
        return NSRect(x: left + CGFloat(column) * Self.pitch, y: cy - Self.dot / 2, width: Self.dot, height: Self.dot)
    }

    func shade(at p: NSPoint) -> Easel.Shade? {
        for (r, row) in Easel.pickerRows.enumerated() {
            for (c, shade) in row.enumerated() where dotRect(row: r, column: c).insetBy(dx: -3, dy: -3).contains(p) { return shade }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        let panel = NSRect(x: 0, y: 0, width: bounds.width, height: Self.panelHeight)
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: bounds.midX - 6, y: Self.panelHeight))
        arrow.line(to: NSPoint(x: bounds.midX, y: bounds.height))
        arrow.line(to: NSPoint(x: bounds.midX + 6, y: Self.panelHeight))
        arrow.close()
        arrow.fill()
        for (r, row) in Easel.pickerRows.enumerated() {
            for (c, shade) in row.enumerated() {
                let d = dotRect(row: r, column: c)
                // The panel's own colours: black stays black and white white here.
                EaselSheetView.color(shade, palette: palette, dark: false).setFill()
                NSBezierPath(ovalIn: d).fill()
                if shade == .black {
                    NSColor(white: 0.15, alpha: 1).setStroke()
                    let ring = NSBezierPath(ovalIn: d.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 1; ring.stroke()
                }
                if shade == current {
                    let mark = NSBezierPath()
                    mark.move(to: NSPoint(x: d.minX + 5.5, y: d.midY + 0.5))
                    mark.line(to: NSPoint(x: d.midX - 1, y: d.maxY - 6))
                    mark.line(to: NSPoint(x: d.maxX - 5, y: d.minY + 6))
                    mark.lineWidth = 2
                    mark.lineCapStyle = .round
                    mark.lineJoinStyle = .round
                    (shade == .white || shade == .yellow ? NSColor.black : NSColor.white).setStroke()
                    mark.stroke()
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let shade = shade(at: convert(event.locationInWindow, from: nil)) { onPick(shade) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Color" }
}
