import AppKit

/// Chrome's bars over a page, drawn by Cra for the Chromium engine (PageInfoBar): Chrome would draw them in its
/// never-shown window. One 40 pt row per bar, top first, as Chrome stacks them: the message, the bar's link and
/// buttons, and its ✕ 20 pt in from the right edge (GitHub #241: the debugger bar's Cancel and ✕ take clicks).
final class InfoBarStrip: NSView {
    /// A press: the bar's id and "ok", "cancel", "link" or "close" (CraBrowser.infoBar(_:action:)).
    var onAction: ((Int, String) -> Void)?

    private(set) var bars: [PageInfoBar] = []
    private var rows: [NSView] = []

    override var isFlipped: Bool { true }

    var height: CGFloat { CGFloat(PageInfoBar.inset(for: bars)) }

    func show(_ bars: [PageInfoBar]) {
        guard bars != self.bars else { return }
        self.bars = bars
        rows.forEach { $0.removeFromSuperview() }
        rows = bars.map(makeRow)
        rows.forEach(addSubview)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = CGFloat(PageInfoBar.height)
        for (i, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)
            layoutRow(row)
        }
    }

    private func makeRow(_ bar: PageInfoBar) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.identifier = .init("line")
        row.addSubview(line)
        let label = NSTextField(labelWithString: bar.message)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.identifier = .init("message")
        row.addSubview(label)
        func button(_ title: String, _ action: String) -> NSButton {
            let b = ActionButton(title: title) { [weak self] in self?.onAction?(bar.id, action) }
            b.bezelStyle = .push
            b.identifier = .init("button")
            return b
        }
        if let link = bar.link {
            let b = button(link, "link")
            b.isBordered = false
            b.contentTintColor = .linkColor
            row.addSubview(b)
        }
        if let ok = bar.ok { row.addSubview(button(ok, "ok")) }
        if let cancel = bar.cancel { row.addSubview(button(cancel, "cancel")) }
        if bar.closeable {
            let close = ActionButton(title: "") { [weak self] in self?.onAction?(bar.id, "close") }
            close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
            close.isBordered = false
            close.imagePosition = .imageOnly
            close.contentTintColor = .secondaryLabelColor
            close.identifier = .init("close")
            row.addSubview(close)
        }
        return row
    }

    /// The ✕ centred 20 pt in from the right edge, the buttons to its left in Chrome's order, the message in what
    /// is left.
    private func layoutRow(_ row: NSView) {
        let b = row.bounds
        var right = b.width
        for v in row.subviews where v.identifier?.rawValue == "close" {
            v.frame = NSRect(x: b.width - 20 - 12, y: (b.height - 24) / 2, width: 24, height: 24)
            right = v.frame.minX - 8
        }
        for v in row.subviews.reversed() where v.identifier?.rawValue == "button" {
            let size = v.fittingSize
            v.frame = NSRect(x: right - size.width, y: (b.height - size.height) / 2, width: size.width, height: size.height)
            right = v.frame.minX - 6
        }
        for v in row.subviews where v.identifier?.rawValue == "message" {
            let h = ceil(v.fittingSize.height)
            v.frame = NSRect(x: 12, y: (b.height - h) / 2, width: max(0, right - 12 - 8), height: h)
        }
        for v in row.subviews where v.identifier?.rawValue == "line" {
            v.frame = NSRect(x: 0, y: b.height - 1, width: b.width, height: 1)
        }
    }

    /// A button that runs a closure.
    private final class ActionButton: NSButton {
        private var handler: () -> Void = {}
        convenience init(title: String, handler: @escaping () -> Void) {
            self.init(frame: .zero)
            self.title = title
            self.handler = handler
            target = self
            action = #selector(fire)
        }
        @objc private func fire() { handler() }
    }
}
