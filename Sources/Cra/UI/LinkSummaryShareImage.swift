import AppKit

/// Copy as Image: the card in light, as Arc 1.171 copies it (a 3x TIFF, 10 Nov 2026). 304 pt wide;
/// the page's picture at its own aspect, inset 2 pt with 8 pt corners; the summary and rows laid
/// out as on screen in #191B1F with #BBBBBC symbols; under a dashed #CFD0FB line (4 pt on, 6 off),
/// a 50 pt #F6F6FF footer with the site's favicon and host on the left and the browser's name
/// in bold on the right, both #9A9AB3.
enum LinkSummaryShareImage {
    private typealias L = LinkSummaryCardLayout
    static let width: CGFloat = 304
    static let footerHeight: CGFloat = 50
    static let brand = "Cra"

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static func render(_ r: LinkSummaryResult, image: NSImage?, favicon: NSImage?) -> NSImage {
        let ink = color(0x191B1F), muted = color(0x9A9AB3)
        let inner = width - 2 * (L.margin + 2)
        let rowWidth = width - (L.rowIndent + 2) - (L.margin + 2)
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = L.lineHeight
        para.maximumLineHeight = L.lineHeight
        let summary = r.quickSummary.map {
            NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink])
        }
        let rows = r.details.map { d -> NSAttributedString in
            let s = NSMutableAttributedString()
            if !d.label.isEmpty { s.append(NSAttributedString(string: d.label + ": ", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold)])) }
            s.append(NSAttributedString(string: d.info, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            s.addAttributes([.foregroundColor: ink, .paragraphStyle: para], range: NSRange(location: 0, length: s.length))
            return s
        }
        func height(_ s: NSAttributedString, _ w: CGFloat) -> CGFloat {
            ceil(s.boundingRect(with: NSSize(width: w, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }
        let banner: CGFloat = image.map { $0.size.width > 0 ? ((width - 4) * $0.size.height / $0.size.width).rounded() : 0 } ?? 0
        var y: CGFloat = banner > 0 ? 2 + banner + 15 : 15
        let summaryY = y
        if let summary { y += height(summary, inner) + L.rowGap }
        var rowYs: [CGFloat] = []
        for row in rows {
            rowYs.append(y)
            y += max(L.lineHeight, height(row, rowWidth)) + L.rowGap
        }
        let separator = (y - L.rowGap + 18).rounded()
        let total = separator + footerHeight
        let size = NSSize(width: width, height: total)

        let scale: CGFloat = 3
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(total * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage(size: size) }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        let cg = ctx.cgContext
        cg.translateBy(x: 0, y: total * scale)
        cg.scaleBy(x: scale, y: -scale)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let image, banner > 0 {
            let rect = NSRect(x: 2, y: 2, width: width - 4, height: banner)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        summary?.draw(with: NSRect(x: L.margin + 2, y: summaryY, width: inner, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let symbolInk = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular).applying(.init(paletteColors: [color(0xBBBBBC)]))
        for (i, row) in rows.enumerated() {
            let ry = rowYs[i]
            if let symbol = (NSImage(systemSymbolName: r.details[i].icon, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil))?.withSymbolConfiguration(symbolInk) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: L.margin + 2 + (18 - s.width) / 2, y: ry + (L.lineHeight - s.height) / 2, width: s.width, height: s.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            row.draw(with: NSRect(x: L.rowIndent + 2, y: ry, width: rowWidth, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        color(0xF6F6FF).setFill()
        NSRect(x: 0, y: separator, width: width, height: footerHeight).fill()
        let dash = NSBezierPath()
        dash.move(to: NSPoint(x: 0, y: separator + 0.5 - 1.0 / 3))
        dash.line(to: NSPoint(x: width, y: separator + 0.5 - 1.0 / 3))
        dash.lineWidth = 1
        dash.setLineDash([4, 6], count: 2, phase: 7)  // a 3 pt gap first, as Arc's
        color(0xCFD0FB).setStroke()
        dash.stroke()
        let mid = separator + footerHeight / 2
        favicon?.draw(in: NSRect(x: L.margin + 2, y: mid - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        let host = NSAttributedString(string: r.host, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: muted])
        host.draw(at: NSPoint(x: L.rowIndent + 2, y: mid - host.size().height / 2))
        let name = NSAttributedString(string: brand, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: muted])
        name.draw(at: NSPoint(x: width - 18 - name.size().width, y: mid - name.size().height / 2))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}
