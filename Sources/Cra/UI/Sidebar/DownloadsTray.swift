import AppKit
import UniformTypeIdentifiers

/// Arc's downloads list: hovering the Library button lists the recent downloads over the
/// bottom of the sidebar, newest at the bottom, and the tab list behind them fades out.
/// Measured on Arc 1.170 (window captures at 60 fps, 27 Oct 2026): rows 56 pt apart, a
/// 40 pt thumbnail with 6 pt corners 8 pt in, the name at x 61 (14 pt, white 82 %) and
/// "54 seconds ago" under it (12 pt, white 50 %); the last row ends 2 pt below the list
/// area. The tab list is hidden from 3 pt above the first row and fades back in over the
/// 170 pt above that. It opens 0.2 s into the hover, rows rising 5 pt and fading in bottom
/// first 25 ms apart; it closes 0.07 s after the pointer leaves.
enum DownloadsTrayMetrics {
    static let rowPitch: CGFloat = 56
    static let thumbnail: CGFloat = 40
    static let fade: CGFloat = 170
    static func listHeight(rows: Int) -> CGFloat { rows == 0 ? 0 : CGFloat(rows) * rowPitch - (rowPitch - thumbnail) }
}

extension SidebarUIState {
    func downloadsHoverChanged() {
        downloadsListWork?.cancel()
        let open = (libraryHovered || downloadsListHovered) && !DownloadHistory.shared.recent.isEmpty
        guard open != downloadsListOpen else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.downloadsListOpen = open } }
        downloadsListWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0.2 : 0.07), execute: work)
    }
}

/// The list itself, pinned to the bottom of the tab list's area.
@MainActor
final class DownloadsTrayView: NSView {
    private let ui: SidebarUIState
    // Every change: the rows' hover and pressed fills are the space's (#896), not only light or dark.
    var colors = SidebarColors() { didSet { if colors != oldValue { for r in rows { r.colors = colors } } } }
    private var rows: [DownloadsTrayRowView] = []
    private var shownOpen = false
    private var ticker: Timer?
    /// How far the view reaches below the rows, down to the Library button's top: while the list is
    /// open, a pointer crossing the player or the banner on its way up keeps it open (#575). It
    /// takes no clicks there; they go to what is under it.
    var reach: CGFloat = 0 { didSet { if reach != oldValue { needsLayout = true } } }
    /// The rows' part of the view.
    private var listRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - reach)) }

    init(ui: SidebarUIState) {
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        ui.downloadsTray = self
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        let (entries, open, _) = withObservationTracking {
            (DownloadHistory.shared.recent, ui.downloadsListOpen, DownloadHistory.shared.thumbnails.count)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        while rows.count < entries.count {
            let r = DownloadsTrayRowView()
            r.colors = colors
            r.alphaValue = shownOpen ? 1 : 0
            r.listOpen = shownOpen
            rows.append(r)
            addSubview(r)
        }
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        for (r, e) in zip(rows, entries) { r.show(e) }
        refreshAges()
        if open != shownOpen { animate(open: open) }
        // TimelineView(.periodic(by: 1)): the ages tick while the list is up.
        if open, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAges() }
            }
        } else if !open {
            ticker?.invalidate()
            ticker = nil
        }
        needsLayout = true
    }

    private func refreshAges() {
        let now = Date()
        for r in rows { r.now = now }
    }

    /// Rows rise 5 pt and fade in bottom first, 25 ms apart; they drop back faster.
    private func animate(open: Bool) {
        shownOpen = open
        for r in rows { r.listOpen = open }
        let n = rows.count
        for (i, r) in rows.enumerated() {
            guard let layer = r.layer else { continue }
            let fromBottom = Double(n - 1 - i)
            let delay = open ? fromBottom * 0.025 : fromBottom * 0.015
            let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
            let fromShift = (layer.presentation()?.value(forKeyPath: "sublayerTransform.translation.y") as? CGFloat) ?? (open ? 5 : 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            r.alphaValue = open ? 1 : 0
            layer.sublayerTransform = CATransform3DMakeTranslation(0, open ? 0 : 5, 0)
            CATransaction.commit()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = open ? 1 : 0
            let move = CABasicAnimation(keyPath: "sublayerTransform.translation.y")
            move.fromValue = fromShift
            move.toValue = open ? 0 : 5
            let group = CAAnimationGroup()
            group.animations = [fade, move]
            group.duration = open ? 0.12 : 0.05
            group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
            layer.add(group, forKey: "openClose")
        }
    }

    override func layout() {
        super.layout()
        // VStack spacing 16 between 40 pt rows, 2 pt lower than the area (.offset(y: 2)). Each row's
        // view is its hover card, 4 pt past the thumbnail above and below (#896).
        let pad = DownloadsTrayRow.pad
        for (i, r) in rows.enumerated() {
            r.frame = NSRect(x: 0, y: 2 + CGFloat(i) * DownloadsTrayMetrics.rowPitch - pad, width: bounds.width,
                             height: DownloadsTrayRow.height(thumbnail: DownloadsTrayMetrics.thumbnail))
        }
    }

    // MARK: Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shownOpen, let superview, listRect.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(holds(convert(event.locationInWindow, from: nil))) }
    override func mouseMoved(with event: NSEvent) { setHovered(holds(convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// Whether the pointer at `p` (in this view) keeps the list open: only an open list holds one.
    private func holds(_ p: NSPoint) -> Bool {
        ui.downloadsListOpen && DownloadsTrayHover.holds(p, list: listRect, buttonTop: bounds.height, open: true)
    }

    /// For `cra://debug?pointerOn=…&under=downloads` (#770): the middle of the open list's first download, in the window.
    var debugFirstRowInWindow: NSPoint? {
        guard shownOpen, !isHidden, let r = rows.first(where: { !$0.isHidden }) else { return nil }
        return r.convert(NSPoint(x: r.bounds.midX, y: r.bounds.midY), to: nil)
    }

    /// For `cra://debug?downloadsTray`: where the list's hover reaches while it is open, and what a press
    /// on the way up from the Library button lands on, as the window's hit test finds it (#575).
    var hoverReadout: String {
        guard let window, let root = window.contentView?.superview, !isHidden, reach > 0 else { return "rows only" }
        let mid = NSPoint(x: bounds.midX, y: listRect.maxY + reach / 2)
        let atButton = NSPoint(x: bounds.midX, y: bounds.height - 1)
        let inWindow = convert(mid, to: nil)
        let hit = root.hitTest(root.superview?.convert(inWindow, from: nil) ?? inWindow)
        let holdsMid = DownloadsTrayHover.holds(mid, list: listRect, buttonTop: bounds.height, open: true)
        let holdsButton = DownloadsTrayHover.holds(atButton, list: listRect, buttonTop: bounds.height, open: true)
        return "reach=\(Int(reach.rounded())) holds=\(holdsMid && holdsButton) press=\(hit === self || hit?.isDescendant(of: self) == true ? "the list" : hit.map { String(describing: type(of: $0)) } ?? "nothing")"
    }

    /// For `cra://debug?downloadsTray=…&row=hover|press|release|leave` (#896): the first row as AppKit
    /// would leave it after that pointer event, and its fill.
    func debugFirstRow(_ action: String?) -> String {
        guard let r = rows.first else { return "row=none" }
        switch action {
        case "hover": r.debugPointer(hovered: true, pressed: false)
        case "press": r.debugPointer(hovered: true, pressed: true)
        case "release": r.debugPointer(hovered: true, pressed: false)
        case "leave": r.debugPointer(hovered: false, pressed: false)
        default: break
        }
        return "row=\(r.fillReadout)"
    }

    private func setHovered(_ h: Bool) {
        guard ui.downloadsListHovered != h else { return }
        ui.downloadsListHovered = h
        ui.downloadsHoverChanged()
    }
}

private final class DownloadsTrayRowView: NSView, NSDraggingSource {
    var colors = SidebarColors() { didSet { refresh() } }
    private var listed: DownloadHistory.Listed?
    /// The finished file this row stands for (live rows have nothing to open or drag yet).
    private var entry: DownloadHistory.Entry? {
        if case .finished(let e)? = listed { return e }
        return nil
    }
    var now = Date() { didSet { refreshAge() } }
    private let thumb = NSView()
    private let name = NSTextField.sidebarLabel(size: 14)
    private let age = NSTextField.sidebarLabel(size: 12)
    private var downAt: NSPoint?
    /// The hover card (#896): the space's hover fill under the pointer, the selected tab's while pressed.
    private let card = CALayer()
    private var hovered = false { didSet { if hovered != oldValue { refreshCard() } } }
    private var pressed = false { didSet { if pressed != oldValue { refreshCard() } } }
    /// The list is up: a closing list lights no row.
    var listOpen = false {
        didSet {
            guard listOpen != oldValue else { return }
            if !listOpen { hovered = false; pressed = false }
            // A list opening under a resting pointer lights the row under it.
            else if let w = window { hovered = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
            refreshCard()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = DownloadsTrayRow.corner
        card.cornerCurve = .continuous
        card.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(card)
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.masksToBounds = true
        thumb.layer?.contentsGravity = .resizeAspectFill
        addSubview(thumb)
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)
        addSubview(age)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Also when only a thumbnail arrived, and on every progress report.
    func show(_ l: DownloadHistory.Listed) {
        listed = l
        refresh()
    }

    private func refresh() {
        let ink: NSColor = colors.isDark ? .white : .black
        name.textColor = ink.withAlphaComponent(0.82)
        age.textColor = ink.withAlphaComponent(0.5)
        refreshCard()
        guard let listed else { return }
        var image: NSImage?
        switch listed {
        case .finished(let e):
            name.stringValue = (e.path as NSString).lastPathComponent
            image = DownloadHistory.shared.thumbnail(for: e.path)
        case .live(let l):
            // Still running, failed or cancelled: the file type's icon, as in the bin before it lands.
            name.stringValue = l.name
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (l.name as NSString).pathExtension) ?? .data)
        }
        if let image {
            // .aspectRatio(contentMode: .fill): the layer fills and crops.
            let scale = window?.backingScaleFactor ?? 2
            var rect = NSRect(x: 0, y: 0, width: DownloadsTrayMetrics.thumbnail, height: DownloadsTrayMetrics.thumbnail)
            thumb.layer?.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
            thumb.layer?.contentsScale = scale
            thumb.layer?.backgroundColor = nil
        } else {
            thumb.layer?.contents = nil
            thumb.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        }
        refreshAge()
    }

    /// "54 seconds ago", "6 minutes ago"; progress, "Failed to Download" or "Cancelled" (DownloadRow).
    private func refreshAge() {
        guard let listed else { return }
        let state: DownloadRow.State
        switch listed {
        case .finished(let e): state = .finished(at: e.date)
        case .live(let l): state = l.row
        }
        let s = DownloadRow.subtitle(state, now: now)
        if age.stringValue != s { age.stringValue = s }
    }

    private var fill: DownloadsTrayRow.Fill {
        DownloadsTrayRow.fill(open: listOpen, hovered: hovered, pressed: pressed, canOpen: entry != nil)
    }

    private func refreshCard() {
        let color: NSColor = switch fill {
        case .none: .clear
        case .hover: colors.hoverFill
        case .pressed: colors.selectedFill
        }
        card.backgroundColor = color.cgColor
    }

    var fillReadout: String { "\(fill)" }

    func debugPointer(hovered h: Bool, pressed p: Bool) {
        hovered = h
        pressed = p
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func layout() {
        super.layout()
        let t = DownloadsTrayMetrics.thumbnail, pad = DownloadsTrayRow.pad
        card.frame = bounds.insetBy(dx: pad, dy: 0)
        thumb.frame = NSRect(x: 8, y: pad, width: t, height: t)
        // HStack(spacing: 13); VStack(spacing: -1) of 17 + 15 with 1 pt on top, centred. The name ends
        // 8 pt inside the hover card, as it starts 8 pt in from the card's thumbnail.
        let x = 8 + t + 13, w = max(0, card.frame.maxX - 8 - x)
        let top = pad + (t - 32) / 2 + 1
        name.frame = NSRect(x: x - SidebarText.inset, y: top, width: w + 2 * SidebarText.inset, height: 17)
        age.frame = NSRect(x: x - SidebarText.inset, y: top + 16, width: w + 2 * SidebarText.inset, height: 15)
    }

    // MARK: Click and drag

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let entry else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: entry.path) as NSURL)
        let image = DownloadHistory.shared.thumbnail(for: entry.path) ?? NSWorkspace.shared.icon(forFile: entry.path)
        item.setDraggingFrame(thumb.frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil; pressed = false }
        guard downAt != nil, let entry, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
    }

    /// Arc's Download Context Menu, as on Library ▸ Downloads (#272): Cancel Download on a running
    /// row, Open, Copy and Show in Finder on a finished one.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let listed else { return nil }
        let menu = NSMenu()
        DownloadRowMenu.fill(menu, for: listed)
        return menu.items.isEmpty ? nil : menu
    }

    /// Dragged out, the row stays picked until the drop (#896).
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pressed = false
        if let w = window { hovered = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }
}
