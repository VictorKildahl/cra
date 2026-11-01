import AppKit
import SwiftUI

/// Arc's command bar: a wide translucent panel, input row with the top match's favicon,
/// single-line rows "Title — url", the selected row tinted with the space color, "Switch to
/// Tab" + arrow for open tabs. AppKit: the rows are reused views that change only what changed,
/// so a keystroke costs the search and a few labels, not a SwiftUI pass over the bar.
@MainActor
final class CommandBarView: NSView {
    static let rowHeight: CGFloat = 50
    static let fieldHeight: CGFloat = 60
    static func height(forRows n: Int) -> CGFloat { fieldHeight + (n == 0 ? 0 : CGFloat(n) * rowHeight + CGFloat(n - 1) * 2 + 20) }

    private let controller: CommandBarController
    private let favicons: FaviconCache
    private let material = NSVisualEffectView()
    private let tint = NSView()
    private let border = CAShapeLayer()
    private let shape = CAShapeLayer()
    private let leadingIcon = NSImageView()
    private let text: CommandTextField
    private let info = NSImageView()
    /// Scoped search: the scope's pill before the field, and "Search YouTube  Tab" at the end of
    /// the row while the typed text would enter it (Arc 1.170, measured at 2x).
    private let pill = NSView()
    private let pillLabel = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let hint = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let keycap = NSView()
    private let keycapLabel = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let divider = NSView()
    private var rows: [CommandBarRowView] = []
    private var syncQueued = false
    private var attached = false

    init(controller: CommandBarController, favicons: FaviconCache) {
        self.controller = controller
        self.favicons = favicons
        text = CommandTextField(controller: controller)
        super.init(frame: .zero)
        wantsLayer = true
        material.blendingMode = .behindWindow
        material.state = .active
        tint.wantsLayer = true
        layer?.mask = shape
        border.fillColor = nil
        border.lineWidth = 2
        leadingIcon.imageScaling = .scaleProportionallyUpOrDown
        leadingIcon.wantsLayer = true
        leadingIcon.layer?.cornerCurve = .continuous
        info.image = SidebarSymbols.image("info.circle", size: 16)
        info.imageScaling = .scaleNone
        info.contentTintColor = .secondaryLabelColor
        divider.wantsLayer = true
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.shadowOpacity = 0.3
        pill.layer?.shadowRadius = 8
        pill.layer?.shadowOffset = .zero
        pillLabel.textColor = .white
        pill.addSubview(pillLabel)
        keycap.wantsLayer = true
        keycap.layer?.cornerRadius = 6
        keycap.layer?.cornerCurve = .continuous
        keycapLabel.stringValue = "Tab"
        keycap.addSubview(keycapLabel)
        for v in [material, tint, leadingIcon, text.field, info, pill, hint, keycap, divider] as [NSView] { addSubview(v) }
        layer?.addSublayer(border)
        border.zPosition = 10
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        sync()
    }

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        syncQueued = false
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
    }

    private func apply() {
        let c = controller
        let items = c.result.items
        let dark = self.dark
        text.update()
        attached = c.attached
        // Closest AppKit materials to SwiftUI's .ultraThinMaterial under the bar's tint (dark: compared
        // pixel for pixel over the same page).
        material.material = dark ? .hudWindow : .popover
        tint.layer?.backgroundColor = (dark ? NSColor.black.withAlphaComponent(0.74) : NSColor.white.withAlphaComponent(0.7)).cgColor
        border.strokeColor = NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.08).cgColor
        divider.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        let scope = c.scope
        // A site's brand colour; the tabs scope takes the space's, the colour of its rows.
        let highlight: NSColor
        if case .site(let site) = scope { highlight = NSColor(hex: site.color) } else { highlight = NSColor(c.highlight) }
        info.isHidden = !c.query.isEmpty || scope != nil
        divider.isHidden = items.isEmpty
        pill.isHidden = scope == nil
        if let scope {
            let color = highlight.withAlphaComponent(1)
            pill.layer?.backgroundColor = color.cgColor
            pill.layer?.shadowColor = color.cgColor
            pillLabel.stringValue = scope.name
        }
        let offered = scope == nil && c.previewText == nil ? c.result.scope : nil
        hint.isHidden = offered == nil
        keycap.isHidden = offered == nil
        if let offered {
            hint.stringValue = "Search \(offered.name)"
            hint.textColor = NSColor.labelColor.withAlphaComponent(0.33)
            keycapLabel.textColor = NSColor.labelColor.withAlphaComponent(0.67)
            keycap.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        }

        // Follows the row the arrows moved to; otherwise the top one.
        let previewing = c.previewText != nil && items.indices.contains(c.selectedIndex)
        let row = previewing ? items[c.selectedIndex] : items.first
        let typed = c.query.trimmingCharacters(in: .whitespaces)
        let glyph = CommandBarGlyph.resolve(
            editingURL: c.mode == .editURL, untouched: !previewing && (typed.isEmpty || typed == c.openedPrefill),
            scoped: scope != nil, pageFaviconKey: c.openedPrefill.flatMap(FaviconKey.key(for:)),
            row: row.map { ($0.faviconKey, $0.symbol) }, hasFavicon: { [favicons] in favicons.image(forKey: $0) != nil })
        if case .favicon(let key) = glyph, let img = favicons.image(forKey: key) {
            leadingIcon.imageScaling = .scaleProportionallyUpOrDown
            leadingIcon.image = img
            leadingIcon.contentTintColor = nil
            leadingIcon.layer?.cornerRadius = 5
            leadingIcon.layer?.masksToBounds = true
            leadingIcon.frame.size = NSSize(width: 20, height: 20)
        } else {
            leadingIcon.imageScaling = .scaleNone
            if case .symbol(let name) = glyph { leadingIcon.image = SidebarSymbols.image(name, size: 17, weight: .medium) }
            leadingIcon.contentTintColor = .secondaryLabelColor
            leadingIcon.layer?.masksToBounds = false
            leadingIcon.frame.size = NSSize(width: 22, height: 22)
        }

        while rows.count < items.count {
            let r = CommandBarRowView()
            r.onHover = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }) else { return }
                if self.controller.selectedIndex != i { self.controller.selectedIndex = i }
            }
            r.onClick = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }), self.controller.result.items.indices.contains(i) else { return }
                self.controller.commit(self.controller.result.items[i])
            }
            rows.append(r)
            addSubview(r)
        }
        for (i, r) in rows.enumerated() {
            guard i < items.count else { r.isHidden = true; continue }
            r.isHidden = false
            let s = items[i]
            r.show(s, icon: s.faviconKey.flatMap { favicons.image(forKey: $0) }, selected: i == c.selectedIndex, highlight: highlight,
                   otherSpace: s.spaceID.flatMap { $0 != c.focusedSpaceID && s.tabID != nil ? c.spaceName($0) : nil },
                   queryEmpty: c.query.isEmpty, dark: dark)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let b = bounds
        material.frame = b
        tint.frame = b
        let top: CGFloat = attached ? 10 : 14
        let path = Self.path(b, top: top, bottom: 14)
        shape.frame = b
        shape.path = path
        border.frame = b
        border.path = path
        // Input row: 22 pt in, icon 22, 14 apart, the field 30 tall, the info glyph at the end.
        let fh = Self.fieldHeight
        let icon = leadingIcon.frame.size
        leadingIcon.frame = NSRect(x: 22 + (22 - icon.width) / 2, y: (fh - icon.height) / 2, width: icon.width, height: icon.height)
        var right = b.width - 22
        if !info.isHidden {
            info.frame = NSRect(x: right - 18, y: (fh - 18) / 2, width: 18, height: 18)
            right -= 18 + 14
        }
        if !keycap.isHidden {
            // Key cap 23 tall, 4 pt around "Tab", 10 pt after the hint.
            let kw = ceil(keycapLabel.attributedStringValue.size().width), kh = keycapLabel.intrinsicContentSize.height
            keycap.frame = NSRect(x: right - kw - 8, y: (fh - 23) / 2, width: kw + 8, height: 23)
            keycapLabel.frame = NSRect(x: 4 - SidebarText.inset, y: (23 - kh) / 2, width: kw + 2 * SidebarText.inset, height: kh)
            right = keycap.frame.minX - 10
            let hw = ceil(hint.attributedStringValue.size().width), hh = hint.intrinsicContentSize.height
            hint.frame = NSRect(x: right - hw - SidebarText.inset, y: (fh - hh) / 2, width: hw + 2 * SidebarText.inset, height: hh)
            right -= hw + 14
        }
        var x: CGFloat = 22 + 22 + 14
        if !pill.isHidden {
            // 23 tall, fully round, 10.5 pt around the name; the field starts 11 pt after it.
            let lw = ceil(pillLabel.attributedStringValue.size().width), lh = pillLabel.intrinsicContentSize.height
            pill.frame = NSRect(x: x, y: (fh - 23) / 2, width: lw + 21, height: 23)
            pill.layer?.cornerRadius = 11.5
            pillLabel.frame = NSRect(x: 10.5 - SidebarText.inset, y: (23 - lh) / 2, width: lw + 2 * SidebarText.inset, height: lh)
            x = pill.frame.maxX + 11
        }
        text.field.frame = NSRect(x: x - 1.5, y: (fh - 30) / 2 + 2, width: max(0, right - x), height: 30)
        divider.frame = NSRect(x: 16, y: fh, width: max(0, b.width - 32), height: 1)
        var y: CGFloat = fh + 10
        for r in rows where !r.isHidden {
            r.frame = NSRect(x: 10, y: y, width: b.width - 20, height: Self.rowHeight)
            y += Self.rowHeight + 2
        }
    }

    /// UnevenRoundedRectangle: smaller top corners while the bar hangs from the toolbar.
    private static func path(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let p = CGMutablePath()
        // Flipped view: minY is the top edge.
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + top), radius: top)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - bottom, y: r.maxY), radius: bottom)
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bottom), radius: bottom)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + top, y: r.minY), radius: top)
        p.closeSubpath()
        return p
    }
}

/// One suggestion: icon, "Title — detail", and "Switch to Tab" + arrow for open tabs.
final class CommandBarRowView: NSView {
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    private let iconBox = NSView()
    private let icon = NSImageView()
    private let emoji = NSTextField.sidebarLabel(size: 16)
    private let label = NSTextField.sidebarLabel(size: 15)
    private let trailing = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private let arrowBox = NSView()
    private let arrow = NSImageView()
    private var shown: (Suggestion, NSImage?, Bool, NSColor, String?, Bool, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 6
        iconBox.layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        arrowBox.wantsLayer = true
        arrowBox.layer?.cornerRadius = 6
        arrowBox.layer?.cornerCurve = .continuous
        arrow.image = SidebarSymbols.image("arrow.right", size: 12, weight: .bold)
        arrow.imageScaling = .scaleNone
        label.lineBreakMode = .byTruncatingMiddle
        trailing.textColor = .secondaryLabelColor
        for v in [iconBox, icon, emoji, label, trailing, arrowBox, arrow] as [NSView] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ s: Suggestion, icon image: NSImage?, selected: Bool, highlight: NSColor, otherSpace: String?, queryEmpty: Bool, dark: Bool) {
        if let o = shown, o.0 == s, o.1 === image, o.2 == selected, o.3 == highlight, o.4 == otherSpace, o.5 == queryEmpty, o.6 == dark { return }
        let sameContent = shown.map { $0.0 == s && $0.1 === image && $0.4 == otherSpace && $0.5 == queryEmpty && $0.6 == dark } ?? false
        shown = (s, image, selected, highlight, otherSpace, queryEmpty, dark)
        layer?.backgroundColor = (selected ? highlight : .clear).cgColor
        guard !sameContent else { return }
        if let image {
            icon.isHidden = false
            emoji.isHidden = true
            iconBox.isHidden = false
            icon.image = image
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = nil
            iconBox.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.06)).cgColor
        } else if case .switchSpace = s.kind, let t = s.trailing {
            icon.isHidden = true
            iconBox.isHidden = true
            emoji.isHidden = false
            emoji.stringValue = t
        } else {
            iconBox.isHidden = true
            emoji.isHidden = true
            icon.isHidden = false
            icon.image = SidebarSymbols.image(s.symbol ?? "globe", size: 15, weight: .medium)
            icon.imageScaling = .scaleNone
            icon.contentTintColor = .secondaryLabelColor
        }
        let t = NSMutableAttributedString(string: s.title, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.labelColor])
        t.append(NSAttributedString(string: Self.detail(s), attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor]))
        label.attributedStringValue = t
        let isTab = s.tabID != nil
        if isTab {
            trailing.font = .systemFont(ofSize: 14, weight: .medium)
            trailing.stringValue = otherSpace ?? (queryEmpty ? "" : "Switch to Tab")
        } else {
            trailing.font = .systemFont(ofSize: 13, weight: .medium)
            trailing.stringValue = s.trailing ?? ""
        }
        arrowBox.isHidden = !isTab
        arrow.isHidden = !isTab
        arrow.contentTintColor = NSColor.labelColor.withAlphaComponent(0.8)
        arrowBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        needsLayout = true
    }

    private static func detail(_ s: Suggestion) -> String {
        switch s.kind {
        case .switchToTab, .search, .command, .switchSpace, .moveToSpace, .moveToFolder: return ""
        case .archived: return s.subtitle.isEmpty ? "" : " — \(s.subtitle)"
        default:
            guard let url = s.url else { return "" }
            let human = SuggestionEngine.humanURL(url)
            return human.lowercased() == s.title.lowercased() ? "" : " — \(human)"
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        // padding 14, icon 26, 14 apart, the title, Spacer(min 8), trailing text, 14, arrow box 22.
        iconBox.frame = NSRect(x: 14, y: (h - 26) / 2, width: 26, height: 26)
        if iconBox.isHidden {
            icon.frame = iconBox.frame
        } else {
            icon.frame = iconBox.frame.insetBy(dx: 4, dy: 4)
        }
        let es = emoji.intrinsicContentSize
        emoji.frame = NSRect(x: 14 + (26 - es.width) / 2, y: (h - es.height) / 2, width: es.width, height: es.height)
        var right = bounds.width - 14
        if !arrowBox.isHidden {
            arrowBox.frame = NSRect(x: right - 22, y: (h - 22) / 2, width: 22, height: 22)
            arrow.frame = arrowBox.frame
            right -= 22 + 14
        }
        if !trailing.stringValue.isEmpty {
            let tw = ceil(trailing.attributedStringValue.size().width)
            let th = trailing.intrinsicContentSize.height
            trailing.frame = NSRect(x: right - tw - SidebarText.inset, y: (h - th) / 2, width: tw + 2 * SidebarText.inset, height: th)
            right -= tw + 14
        } else if !arrowBox.isHidden {
            // The empty label still takes its spacing in the HStack.
            right -= 14
        }
        let x: CGFloat = 14 + 26 + 14
        let ls = label.intrinsicContentSize
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - ls.height) / 2, width: max(0, right - 8 - x) + 2 * SidebarText.inset, height: ls.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}
