import AppKit
import UniformTypeIdentifiers

/// What the canvas asks of the rest of the app (EaselServices.swift fills these in at launch; the
/// canvas tests leave them empty, and the canvas does without).
@MainActor
enum EaselHooks {
    /// Opens an address in a new tab, as a link card's click does.
    static var openURL: ((String) -> Void)?
    /// Reads a page's og: tags, its picture and its icon for a link card.
    static var fetchLink: ((String, @escaping @MainActor (EaselLinkMetadata?, _ picture: Data?, _ icon: Data?) -> Void) -> Void)?
    /// A dragged sidebar row (its .craSidebarItem payload) as an address and title.
    static var sidebarLink: ((Data) -> (url: String, title: String)?)?
    /// The site's icon for a capture's hover bar.
    static var favicon: ((String) -> NSImage?)?
    /// The live page behind a capture (EaselLivePage).
    static var live: ((Easel.Capture, String?) -> EaselLive?)?
}

/// A capture's live page, as the canvas sees it.
@MainActor
protocol EaselLive: AnyObject {
    var onFrame: (NSImage) -> Void { get set }
    var onFail: () -> Void { get set }
    func click(at p: Easel.Point, open: @escaping (String) -> Void)
    func close()
}

extension NSPasteboard.PasteboardType {
    /// Easel items copied in Cra (Arc: company.thebrowser.Browser.easelObject): their JSON, and the
    /// easel whose pictures they name.
    static let craEaselItems = NSPasteboard.PasteboardType("dk.kildahl.cra.easel-items")
    /// A sidebar row being dragged (SpaceListView's .craSidebarItem).
    static let easelSidebarRow = NSPasteboard.PasteboardType("dk.kildahl.cra.sidebar-item")
}

/// What ⌘C puts on the pasteboard: the items and where their pictures are.
struct EaselClip: Codable {
    var easel: UUID
    var items: [Easel.Item]
}

/// Arc's Easel canvas (Arc 1.172.1, `easelCanvasView`): as wide as the page area and 2436 pt
/// tall, scrolling; the title box 894 pt wide, centred, 52 pt down, bold white; a toolbar at the
/// bottom left, 16 pt in: 36 pt buttons 38 pt apart on the palette's dark backgroundExtra, the
/// picked tool on a lighter fill with 8 pt corners, glyphs in its foreground. Shapes, arrows and
/// strokes are drawn with a drag, text with a click, pictures from a file or the clipboard.
@MainActor
final class EaselCanvasView: NSView {
    private(set) var document: Easel
    var onTitle: (String) -> Void = { _ in }
    private let store: JSONStore<Easel>
    private let scroll = NSScrollView()
    private let sheet: EaselSheetView
    private let toolbar = EaselToolbar()

    init(document: Easel) {
        self.document = document
        store = EaselFiles.store(document.id)
        sheet = EaselSheetView(document: document)
        super.init(frame: .zero)
        EaselFiles.opened(self)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        // Endless in every direction, and zoomable (#580; Arc: fixed width, grows down).
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = Easel.zoomRange.lowerBound
        scroll.maxMagnification = Easel.zoomRange.upperBound
        scroll.documentView = sheet
        scroll.contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        center.addObserver(self, selector: #selector(settleNow), name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        center.addObserver(self, selector: #selector(settleNow), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        addSubview(scroll)
        addSubview(toolbar)
        sheet.onChange = { [weak self] doc in self?.changed(doc) }
        sheet.onDragged = { [weak self] in self?.updateExtent(shrink: false) }
        sheet.onToolDone = { [weak self] in self?.toolbar.tool = .pointer; self?.sheet.tool = .pointer }
        toolbar.onDuplicate = { [weak self] in self?.sheet.duplicateSelected() }
        let pick: (Easel.Tool) -> Void = { [weak self] tool in
            guard let self else { return }
            if tool == .image { self.sheet.addPictureFromFile(); return }
            self.sheet.tool = tool
            self.toolbar.tool = tool
        }
        toolbar.onPick = pick
        // A tool's key, pressed on the canvas, picks it as a click on its button does.
        sheet.onToolKey = pick
    }

    var toolbarView: EaselToolbar { toolbar }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func changed(_ doc: Easel) {
        let renamed = doc.title != document.title
        document = doc
        settle()
        if EaselFiles.deleted.contains(doc.id) {
            // Drawn on after its file went (a reopened tab or Peek): the user is making it again.
            guard !FileManager.default.fileExists(atPath: store.url.path) else { return }
            EaselFiles.deleted.remove(doc.id)
            EaselFiles.listChanged()
        }
        edited = true
        store.save(doc)
        if renamed {
            onTitle(doc.title)
            EaselFiles.listChanged()
        }
    }

    /// Changed since it opened: an easel with no file (a row whose easel was deleted) is written only then.
    private var edited = false

    /// Closing: what is not on disk yet. A deleted easel's tab writes nothing back.
    func saveNow() { if edited, !EaselFiles.deleted.contains(document.id) { store.saveNow(document) } }

    func focus() { window?.makeFirstResponder(sheet) }

    /// The profile of the tab the easel is in: live captures load there.
    var profilePath: String? {
        get { sheet.profilePath }
        set { sheet.profilePath = newValue }
    }

    func closeLives() { sheet.closeLives() }

    /// A change made elsewhere (sync's merge): shown as Undo shows a step, saved, and not undoable.
    func replace(with easel: Easel) { sheet.replace(with: easel) }

    var sheetView: EaselSheetView { sheet }


    override func layout() {
        super.layout()
        scroll.frame = bounds
        updateExtent(shrink: true)
        toolbar.frame = NSRect(x: 16, y: bounds.height - 16 - EaselToolbarLayout.height,
                               width: EaselToolbarLayout.width, height: EaselToolbarLayout.height)
    }

    // MARK: The endless canvas (#580)

    /// The sheet's bounds are the part of the endless canvas that exists now (`Easel.extent`), in the
    /// items' own points, so an item can sit anywhere, left of or above the home sheet too.
    private var adjusting = false
    private var placed = false

    @objc private func scrolled() { updateExtent(shrink: false) }
    @objc private func settleNow() { settle() }

    /// Fit the canvas round what is there now, once a scroll, zoom or edit is over.
    func settle() { updateExtent(shrink: true) }

    /// Grow (or, with `shrink`, fit) the canvas to the home sheet, the items and the view, with a
    /// view's room past them. When its top or left edge moves, the view moves by as much, so the
    /// canvas under it stays put.
    func updateExtent(shrink: Bool) {
        guard !adjusting, bounds.width > 0, bounds.height > 0 else { return }
        let clip = scroll.contentView
        let home = Easel.home(width: max(Double(bounds.width), 300))
        sheet.home = NSRect(x: home.x, y: home.y, width: home.width, height: home.height)
        // Before the first fit the view is on the home sheet's top left.
        let visible = placed ? sheet.visibleRect : NSRect(origin: .zero, size: clip.bounds.size)
        let current = sheet.bounds
        let e = Easel.extent(home: home, items: sheet.document.items.map(\.frame),
                             visible: .init(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
                             keeping: shrink || !placed ? nil : .init(x: current.minX, y: current.minY, width: current.width, height: current.height))
        let extent = NSRect(x: e.x, y: e.y, width: e.width, height: e.height)
        if placed, extent == current { return }
        adjusting = true
        defer { adjusting = false }
        sheet.setFrameSize(extent.size)
        sheet.setBoundsOrigin(extent.origin)
        clip.scroll(to: NSPoint(x: visible.minX - extent.minX, y: visible.minY - extent.minY))
        scroll.reflectScrolledClipView(clip)
        placed = true
    }

    /// View ▸ Zoom In, Zoom Out and Actual Size (⌘+ ⌘− ⌘0) on an easel: its magnification, in a
    /// page's zoom steps, round the middle of the view.
    var zoomLevel: Double {
        get { Easel.zoomLevel(magnification: Double(scroll.magnification)) }
        set {
            let visible = sheet.visibleRect
            let middle = NSPoint(x: visible.midX, y: visible.midY)
            adjusting = true
            scroll.magnification = CGFloat(Easel.magnification(zoomLevel: newValue))
            adjusting = false
            // Grow the canvas round the new view first, then put the same canvas point back in its middle,
            // measured on the view as it is (insets and scrollers included).
            updateExtent(shrink: false)
            let clip = scroll.contentView
            let now = sheet.visibleRect
            clip.scroll(to: NSPoint(x: clip.bounds.minX + middle.x - now.midX, y: clip.bounds.minY + middle.y - now.midY))
            scroll.reflectScrolledClipView(clip)
            settle()
        }
    }
}

/// The drawing itself.
@MainActor
final class EaselSheetView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    private(set) var document: Easel
    var tool: Easel.Tool = .pointer { didSet { window?.invalidateCursorRects(for: self); placeColorPicker() } }
    var onChange: (Easel) -> Void = { _ in }
    var onToolDone: () -> Void = {}
    /// Items moved under a drag: the canvas grows to take them in (#580).
    var onDragged: () -> Void = {}
    /// The home sheet the title is centred over (#580: the canvas around it has no edge). Unset, the bounds.
    var home: NSRect? { didSet { if home != oldValue { needsLayout = true } } }
    /// A tool's key was pressed (Arc: V, I, T, O, R, A, P), or Escape with a tool in hand.
    var onToolKey: (Easel.Tool) -> Void = { _ in }
    /// Arc's capture editor (#851): the sheet lies over a capture, with no title.
    var editsImage = false { didSet { title.isHidden = editsImage } }
    private let title = EaselTextField()
    private var texts: [UUID: NSTextField] = [:]
    /// The picked items, in the order they were picked (#580: ⌘- or ⇧-click and the drag box pick several).
    private(set) var picked: [UUID] = [] {
        didSet {
            guard picked != oldValue else { return }
            if !picked.isEmpty { titlePicked = false }
            needsDisplay = true; placeSizePill(); window?.invalidateCursorRects(for: self)
        }
    }
    /// The one picked item, when only one is: it alone shows corner handles, the size pill and a live page.
    private var selected: UUID? {
        get { picked.count == 1 ? picked[0] : nil }
        set { picked = newValue.map { [$0] } ?? [] }
    }
    /// The box being drawn from empty canvas, and the picks from before it (#580).
    private(set) var band: Easel.Rect?
    private var bandBefore: [UUID] = []
    /// ⌘ or ⇧ was held when the drag started.
    private var extending = false
    /// A plain click on an item of a picked group: it alone is picked if the click doesn't become a drag.
    private var soloOnUp: UUID?
    /// A corner of the picked item being dragged (Arc's AspectRatioControlPoints).
    private var resizing: (corner: Easel.Corner, from: Easel.Rect)?
    /// The title box is being typed in: the pill acts on it.
    private var titlePicked = false { didSet { placeSizePill() } }
    /// Arc's black pill beside a picked text box: +, Aa, − (text size).
    private let sizePill = EaselSizePill()
    /// Arc's colour picker over a picked shape.
    let colorPicker = EaselColorPicker()
    private var dragStart: Easel.Point?
    private var dragLast: Easel.Point?
    private var preview: Easel.Item?
    private var stroke: [Easel.Point] = []
    private var images: [String: NSImage] = [:]
    /// Undo and Redo (Edit ▸ Undo ⌘Z): the easel before each change.
    private(set) var history = EaselHistory()
    /// The easel before a drag that moves or resizes, recorded once the drag really moves.
    private var dragBefore: Easel?
    /// Arc's alignment guides while an item moves.
    private var guides: [Easel.Guide] = []
    static let guidesKey = "easelAlignmentGuides"
    static var usesGuides: Bool {
        get { UserDefaults.standard.object(forKey: guidesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: guidesKey) }
    }
    /// Live captures: their pages, and the latest picture of each.
    private var lives: [UUID: EaselLive] = [:]
    private(set) var liveImages: [UUID: NSImage] = [:]
    private(set) var liveFrameCount = 0
    /// The profile the easel's tab is in, for live pages.
    var profilePath: String?
    /// The capture under the pointer: its hover bar shows.
    private var hovered: UUID? { didSet { if hovered != oldValue { needsDisplay = true } } }
    /// The canvas is dark: Arc's palette swaps black and white.
    static let dark = true

    static let ink = NSColor(white: 1, alpha: 0.92)
    static let selection = NSColor(srgbRed: 0.47, green: 0.71, blue: 0.95, alpha: 1)
    static let arcSelection = NSColor(srgbRed: 127 / 255, green: 184 / 255, blue: 214 / 255, alpha: 1)

    init(document: Easel) {
        self.document = document
        super.init(frame: .zero)
        title.stringValue = document.title
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.alignment = .center
        title.font = Self.font(document.titleStyle, size: document.titleSize ?? 34, title: true)
        title.textColor = .white
        title.placeholderString = "Untitled Easel"
        title.delegate = self
        title.onFocus = { [weak self] in self?.selected = nil; self?.titlePicked = true }
        addSubview(title)
        sizePill.isHidden = true
        sizePill.onStep = { [weak self] step in self?.resizeSelectedText(by: step) }
        sizePill.onStyle = { [weak self] in self?.cycleSelectedStyle() }
        addSubview(sizePill)
        colorPicker.isHidden = true
        colorPicker.onPick = { [weak self] shade in self?.setShade(shade) }
        addSubview(colorPicker)
        // Boxes saved by Cra before #580 are one 240 pt line whatever their text: fit them to it.
        for i in self.document.items.indices {
            if case .text(let string, let size) = self.document.items[i].kind {
                self.document.items[i].frame = fittedTextFrame(self.document.items[i], string: string, size: size)
            }
        }
        for item in document.items { if case .text = item.kind { addTextField(for: item) } }
        registerForDraggedTypes([.fileURL, .png, .tiff, .URL, .string, .easelSidebarRow])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The window moves by its background: a drag here draws instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let field = hit as? EaselTextField, field !== title, field.currentEditor() == nil { return self }
        return hit
    }

    override func layout() {
        super.layout()
        let area = home ?? bounds
        let w = min(CGFloat(Easel.titleWidth), area.width - 40)
        title.frame = NSRect(x: area.minX + (area.width - w) / 2, y: CGFloat(Easel.titleTop) + 24, width: w, height: 48)
        for item in document.items { texts[item.id]?.frame = rect(item.frame) }
    }

    private func rect(_ r: Easel.Rect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }

    /// Nothing picked and no text being typed: the drawing as it goes into a capture (#851).
    func clearPicks() {
        window?.makeFirstResponder(self)
        picked = []
        needsDisplay = true
    }

    private func point(_ e: NSEvent) -> Easel.Point { let p = convert(e.locationInWindow, from: nil); return .init(p.x, p.y) }

    /// A change, undoable as `name` (Arc's undo labels: Move, Delete, Paste…).
    private func commit(_ name: String = "Change", record: Bool = true, _ change: (inout Easel) -> Void) {
        let before = document
        change(&document)
        guard document != before else { return }
        if record { history.record(before, name) }
        needsDisplay = true
        onChange(document)
        syncLives()
    }

    /// The easel as it was or will be again (Undo, Redo): text boxes, pictures and live pages follow.
    private func show(_ easel: Easel) {
        document = easel
        let ids = Set(easel.items.map(\.id))
        for (id, f) in texts where !ids.contains(id) { f.removeFromSuperview(); texts[id] = nil }
        for item in easel.items {
            guard case .text(let string, let size) = item.kind else { continue }
            if let f = texts[item.id] {
                if f.stringValue != string { f.stringValue = string }
                f.font = Self.font(item.style, size: size, title: false)
                f.textColor = textColor(of: item)
                f.frame = rect(item.frame)
            } else {
                addTextField(for: item)
            }
        }
        if title.stringValue != easel.title, easel.title != "Untitled Easel" || !title.stringValue.isEmpty { title.stringValue = easel.title }
        title.font = Self.font(easel.titleStyle, size: easel.titleSize ?? 34, title: true)
        picked = picked.filter(ids.contains)
        placeSizePill()
        needsDisplay = true
        onChange(document)
        syncLives()
    }

    /// The easel as changed elsewhere: nothing before it can be undone, so ⌘Z never takes the change back.
    func replace(with easel: Easel) {
        history = EaselHistory()
        dragBefore = nil
        show(easel)
    }

    @objc func undo(_ sender: Any?) {
        window?.makeFirstResponder(self)
        if let back = history.undo(document) { show(back) }
    }

    @objc func redo(_ sender: Any?) {
        if let next = history.redo(document) { show(next) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for item in document.items + [preview].compactMap({ $0 }) { draw(item) }
        if stroke.count > 1, let s = Easel.freehand(stroke) { draw(s) }
        for item in document.items where picked.contains(item.id) {
            if Easel.resizes(item.kind) {
                // Arc 1.172.1: a square 2 pt outline on the item's edge (#7FB8D6) and, at each corner,
                // a 7.5 pt ring of it round a 3 pt dark dot (8 Nov 2026, 2x stills). A text box keeps its rounded
                // outline, with the same four dots at its corners and none on its edges (Arc 1.174.1, #680).
                let isText: Bool = { if case .text = item.kind { return true }; return false }()
                let r = isText ? rect(item.frame).insetBy(dx: -4, dy: -4) : rect(item.frame)
                if isText {
                    Self.selection.setStroke()
                    let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                    path.lineWidth = 2
                    path.stroke()
                } else {
                    Self.arcSelection.setStroke()
                    let path = NSBezierPath(rect: r.insetBy(dx: -1, dy: -1))
                    path.lineWidth = 2
                    path.stroke()
                }
                // Handles only when it is picked alone: a group doesn't resize.
                guard picked.count == 1 else { continue }
                for c in [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)] {
                    Self.arcSelection.setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 3.75, y: c.y - 3.75, width: 7.5, height: 7.5)).fill()
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
                }
            } else if case .link = item.kind {
                // Arc: the card's own rounded edge, in the selection blue, no handles.
                Self.arcSelection.setStroke()
                let path = NSBezierPath(roundedRect: rect(item.frame).insetBy(dx: -1, dy: -1), xRadius: 11, yRadius: 11)
                path.lineWidth = 2
                path.stroke()
            } else {
                let r = rect(item.frame).insetBy(dx: -4, dy: -4)
                Self.selection.setStroke()
                let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                path.lineWidth = 2
                path.stroke()
            }
        }
        // The selection box a drag from empty canvas draws (#580), as Finder's: a light fill, a thin edge.
        if let band {
            let r = rect(band)
            Self.arcSelection.withAlphaComponent(0.15).setFill()
            r.fill()
            Self.arcSelection.withAlphaComponent(0.8).setStroke()
            let edge = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
        }
        // Arc's alignment guides: a thin line along the edge a moving item shares.
        Self.arcSelection.setStroke()
        for g in guides {
            let p = NSBezierPath()
            if g.axis == .vertical { p.move(to: NSPoint(x: g.position, y: g.from)); p.line(to: NSPoint(x: g.position, y: g.to)) }
            else { p.move(to: NSPoint(x: g.from, y: g.position)); p.line(to: NSPoint(x: g.to, y: g.position)) }
            p.lineWidth = 1
            p.stroke()
        }
    }

    /// A shade as Arc draws it: its hex in sRGB, or in Display P3 for the two Arc keeps there.
    static func color(_ shade: Easel.Shade, palette: Easel.Palette?, dark: Bool) -> NSColor {
        let hex = Easel.hex(shade, palette: palette, dark: dark)
        guard Easel.isDisplayP3(shade), let c = HexColor.components(hex) else { return NSColor(hexString: hex) ?? Self.ink }
        return NSColor(displayP3Red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// A shape's colour: its shade in the easel's palette (an older easel's #RRGGBB, else the default).
    private func color(of item: Easel.Item) -> NSColor {
        if let shade = item.shade ?? (item.color == nil ? Easel.defaultShade(item.kind) : nil) {
            return Self.color(shade, palette: document.palette, dark: Self.dark)
        }
        return item.color.flatMap { NSColor(hexString: $0) } ?? Self.ink
    }

    private func draw(_ item: Easel.Item) {
        let color = color(of: item)
        let r = rect(item.frame)
        // Arc's shapes (EaselShapeView, its export viewer's renderShape): filled at 75 % and stroked
        // 2.5 pt in the same colour, round joins and caps.
        func paint(_ p: NSBezierPath, fill: Bool) {
            if fill { color.withAlphaComponent(Easel.shapeFillOpacity).setFill(); p.fill() }
            color.setStroke()
            p.lineWidth = Easel.shapeStroke
            p.lineJoinStyle = .round
            p.lineCapStyle = .round
            p.stroke()
        }
        switch item.kind {
        case .rectangle:
            paint(NSBezierPath(rect: r), fill: true)
        case .ellipse:
            paint(NSBezierPath(ovalIn: r), fill: true)
        case .arrow(let a, let b):
            // Arc's CGPath+Easel arrow: two flares at the tip, 45° off the line, min(32, 0.3 × length) long.
            let p = NSBezierPath()
            p.move(to: NSPoint(x: a.x, y: a.y)); p.line(to: NSPoint(x: b.x, y: b.y))
            let dx = a.x - b.x, dy = a.y - b.y, length = max(hypot(dx, dy), 1)
            let k = min(32, 0.3 * length) / length
            for angle in [Double.pi / 4, -Double.pi / 4] {
                let fx = dx * k * cos(angle) - dy * k * sin(angle), fy = dx * k * sin(angle) + dy * k * cos(angle)
                p.move(to: NSPoint(x: b.x + fx, y: b.y + fy)); p.line(to: NSPoint(x: b.x, y: b.y))
            }
            paint(p, fill: false)
        case .freehand(let pts):
            guard let first = pts.first else { return }
            let p = NSBezierPath()
            p.move(to: NSPoint(x: first.x, y: first.y))
            for q in pts.dropFirst() { p.line(to: NSPoint(x: q.x, y: q.y)) }
            paint(p, fill: false)
        case .image(let file):
            picture(file)?.draw(in: r)
        case .link(let link):
            EaselCards.drawLink(link, in: r, picture: link.image.flatMap(picture), favicon: link.icon.flatMap(picture) ?? EaselHooks.favicon?(link.url))
        case .capture(let capture):
            let shot = liveImages[item.id] ?? picture(capture.image)
            EaselCards.drawCapture(capture, in: r, picture: shot, live: liveImages[item.id] != nil,
                                   hovered: hovered == item.id, favicon: EaselHooks.favicon?(capture.url))
        case .text:
            break  // a text field of its own
        }
    }

    private func picture(_ file: String) -> NSImage? {
        if let cached = images[file] { return cached }
        let image = NSImage(contentsOf: EaselFiles.pictures(document.id).appendingPathComponent(file))
        images[file] = image
        return image
    }

    // MARK: Tools

    private func item(_ id: UUID?) -> Easel.Item? { id.flatMap { id in document.items.first { $0.id == id } } }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        titlePicked = false
        let p = point(event)
        dragStart = p
        dragLast = p
        dragBefore = nil
        band = nil
        soloOnUp = nil
        switch tool {
        case .pointer:
            // ⌘ or ⇧ adds the clicked item to the picks or takes it out, as everywhere on the Mac (#580).
            extending = !event.modifierFlags.isDisjoint(with: [.command, .shift])
            let hit = document.item(at: p)
            if extending {
                picked = Easel.picked(picked, click: hit?.id, extend: true)
                if hit == nil { band = Easel.Rect(from: p, to: p); bandBefore = picked }
                // An item just taken out isn't dragged.
                if let hit, !picked.contains(hit.id) { dragStart = nil }
                return
            }
            // A corner of the picked picture, shape or text, or anywhere along a shape's or text box's edge (Arc's
            // ExtendedDragArea, #680), resizes it; anywhere else picks (and moves).
            if let item = item(selected), Easel.resizes(item.kind), let corner = Easel.corner(of: item.frame, at: p, kind: item.kind) {
                resizing = (corner, item.frame)
                return
            }
            // Empty canvas starts a selection box.
            if hit == nil {
                picked = []
                band = Easel.Rect(from: p, to: p)
                bandBefore = []
                return
            }
            // A capture's ↗ chip opens its page (Arc's hover bar).
            if let hit, case .capture(let c) = hit.kind, hovered == hit.id, EaselCards.chipRect(in: rect(hit.frame)).contains(NSPoint(x: p.x, y: p.y)) {
                EaselHooks.openURL?(c.url)
                dragStart = nil
                return
            }
            // A link card's ↗ opens the page.
            if let hit, case .link(let l) = hit.kind, EaselCards.linkChipRect(in: rect(hit.frame)).contains(NSPoint(x: p.x, y: p.y)) {
                EaselHooks.openURL?(l.url)
                dragStart = nil
                return
            }
            // A click on a picked live capture reaches its page.
            if let hit, hit.id == selected, event.clickCount == 1, case .capture = hit.kind, let live = lives[hit.id] {
                let f = hit.frame
                if case .capture(let c) = hit.kind, let area = c.area, f.width > 0 {
                    let k = area.width / f.width
                    live.click(at: .init((p.x - f.x) * k, (p.y - f.y) * k)) { EaselHooks.openURL?($0) }
                }
            }
            // A click on an item of a picked group keeps the group, to drag it; let go without a drag
            // and that item is picked alone.
            if let hit, picked.count > 1, picked.contains(hit.id), event.clickCount == 1 { soloOnUp = hit.id }
            picked = Easel.picked(picked, click: hit?.id, extend: false)
            if event.clickCount == 2, let hit {
                selected = hit.id
                dragStart = nil
                dragLast = nil
                if let field = texts[hit.id] { field.selectText(nil) }
                // A double click opens a link or a capture's page in a tab.
                switch hit.kind {
                case .link(let l): EaselHooks.openURL?(l.url)
                case .capture(let c): EaselHooks.openURL?(c.url)
                default: break
                }
            }
        case .text:
            let item = Easel.Item(kind: .text("", size: 18), frame: .init(x: p.x, y: p.y - 12, width: 240, height: 26))
            commit("Add Text") { $0.items.append(item) }
            addTextField(for: item)
            selected = item.id
            window?.makeFirstResponder(texts[item.id])
            onToolDone()
        case .freehand:
            stroke = [p]
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let last = dragLast else { return }
        // A drag past the view's edge scrolls on: the canvas has no edge (#580).
        autoscroll(with: event)
        defer { onDragged() }
        let p = point(event)
        dragLast = p
        switch tool {
        case .pointer:
            _ = last
            // The selection box: the items it touches are picked as it grows (#580).
            if band != nil {
                band = Easel.Rect(from: start, to: p)
                picked = Easel.picked(bandBefore, band: document.touching(band!), extend: extending)
                needsDisplay = true
                return
            }
            guard !picked.isEmpty else { return }
            soloOnUp = nil
            if dragBefore == nil { dragBefore = document }
            if let r = resizing, let id = selected, let i = document.items.firstIndex(where: { $0.id == id }) {
                if case .text(let string, let size) = document.items[i].kind {
                    // Arc: a corner or the left or right edge sets the width, the other side fixed, and the text
                    // wraps at it; the top and bottom edges move nothing, as the height is the text's (#680).
                    guard let w = Easel.resizedText(r.from, corner: r.corner, to: p) else { return }
                    var item = document.items[i]
                    item.frame = Easel.Rect(x: w.x, y: r.from.y, width: w.width, height: r.from.height)
                    item.fixedWidth = true
                    item.frame = fittedTextFrame(item, string: string, size: size)
                    document.items[i] = item
                    texts[id]?.frame = rect(item.frame)
                    placeSizePill()
                    placeColorPicker()
                    needsDisplay = true
                    return
                }
                let keep = Easel.keepsRatio(document.items[i].kind) || event.modifierFlags.contains(.shift)
                document.items[i].frame = Easel.resized(r.from, corner: r.corner, to: p, keepRatio: keep)
                placeColorPicker()
                needsDisplay = true
                return
            }
            // Where the drag puts the picked items, then onto their neighbours' edges as one box (Use
            // Alignment Guides; ⌘ held doesn't snap).
            guard let before = dragBefore else { return }
            let snap = Self.usesGuides && !event.modifierFlags.contains(.command)
            let moved = before.moving(picked, by: .init(p.x - start.x, p.y - start.y), snap: snap)
            document = moved.easel
            guides = moved.guides
            for id in picked { if let item = item(id) { texts[id]?.frame = rect(item.frame) } }
            placeSizePill()
            needsDisplay = true
        case .freehand:
            stroke.append(p)
            needsDisplay = true
        default:
            preview = Easel.Item.drawn(tool, from: start, to: p)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragLast = nil; preview = nil; stroke = []; resizing = nil; dragBefore = nil; guides = []; band = nil; soloOnUp = nil }
        switch tool {
        case .pointer:
            if let solo = soloOnUp, dragBefore == nil { selected = solo }
            if let before = dragBefore, before != document {
                history.record(before, resizing == nil ? "Move" : "Resize")
                onChange(document)
                window?.invalidateCursorRects(for: self)
            }
        case .freehand:
            if stroke.count > 1, let item = Easel.freehand(stroke) { commit("Draw") { $0.items.append(item) }; selected = nil }
        default:
            // A drag draws the box it spans; a click places Arc's 200 pt rectangle or ellipse.
            if let start = dragStart, let item = Easel.shape(tool, from: start, to: point(event)) {
                commit("Draw") { $0.items.append(item) }
                selected = item.id
                onToolDone()
            }
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    /// The capture under the pointer shows its hover bar.
    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        let hit = document.item(at: p)
        if let hit, case .capture = hit.kind { hovered = hit.id } else { hovered = nil }
        // Arc's tooltip over a link card: its whole title and its address.
        if let hit, case .link(let l) = hit.kind {
            let tip = [l.title, l.url].compactMap { $0 }.joined(separator: "\n")
            if toolTip != tip { toolTip = tip }
        } else if toolTip != nil {
            toolTip = nil
        }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, !picked.isEmpty {  // Delete, Forward Delete
            deleteSelected()
        } else if event.keyCode == 53 {
            picked = []
            // Arc: Escape with a tool in hand goes back to the pointer.
            if tool != .pointer { onToolKey(.pointer) }
        } else if let picked = Easel.Tool.picked(byKey: event.charactersIgnoringModifiers ?? "",
                                                 command: event.modifierFlags.contains(.command),
                                                 control: event.modifierFlags.contains(.control),
                                                 option: event.modifierFlags.contains(.option)) {
            onToolKey(picked)
        } else {
            super.keyDown(with: event)
        }
    }

    /// A capture sent here from a page (the capture menu's row for this easel): on the canvas at
    /// once, picked, and in view.
    func insert(_ item: Easel.Item) {
        commit("Add Capture") { $0.items.append(item) }
        selected = item.id
        scrollToVisible(rect(item.frame).insetBy(dx: -40, dy: -40))
    }

    func deleteSelected() {
        let ids = picked
        guard !ids.isEmpty else { return }
        for id in ids { texts.removeValue(forKey: id)?.removeFromSuperview() }
        picked = []
        commit("Delete") { $0.items.removeAll { ids.contains($0.id) } }
    }

    /// Edit ▸ Select All (⌘A) on the canvas: every item (#580).
    override func selectAll(_ sender: Any?) {
        window?.makeFirstResponder(self)
        picked = document.items.map(\.id)
    }

    // MARK: Menus (Arc's EaselObjectMenuProvider and EaselCanvasMenuProvider)

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = point(event)
        if let hit = document.item(at: p) {
            // A right click on one of several picked items acts on them all (#580).
            if !picked.contains(hit.id) { selected = hit.id }
            return objectMenu(for: hit)
        }
        picked = []
        return canvasMenu(at: NSPoint(x: p.x, y: p.y))
    }

    private func add(_ menu: NSMenu, _ title: String, key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true, _ run: @escaping () -> Void) {
        let item = EaselMenuItem(title: title, run: run)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.isEnabled = enabled
        menu.addItem(item)
    }

    /// Arc 1.172.2's object menu (EaselObjectMenuProvider, read over AX 11 Nov 2026): Bring to Front,
    /// Send to Back, Delete, —, Cut, Copy, Paste, —, Duplicate. Its other rows (alt text, the easel's
    /// thumbnail, a capture's address) follow for the kinds they belong to.
    /// With several items picked (#580) the rows act on them all, and the rows for one kind are left out.
    func objectMenu(for item: Easel.Item) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let id = item.id
        let group = picked.count > 1 && picked.contains(id) ? picked : [id]
        add(menu, "Bring to Front", enabled: !document.isFront(group)) { [weak self] in self?.commit("Bring to Front") { $0.bringToFront(group) } }
        add(menu, "Send to Back", enabled: !document.isBack(group)) { [weak self] in self?.commit("Send to Back") { $0.sendToBack(group) } }
        add(menu, "Delete") { [weak self] in self?.deleteSelected() }
        menu.addItem(.separator())
        add(menu, "Cut", key: "x") { [weak self] in self?.cut(nil) }
        add(menu, "Copy", key: "c") { [weak self] in self?.copy(nil) }
        add(menu, "Paste", key: "v", enabled: canPaste) { [weak self] in self?.paste(nil) }
        menu.addItem(.separator())
        add(menu, "Duplicate") { [weak self] in self?.duplicateSelected() }
        var extra: [() -> Void] = []
        guard group.count == 1 else { return menu }
        switch item.kind {
        case .capture(let c):
            if c.canGoLive {
                if c.live == true {
                    extra.append { self.add(menu, "Show Screenshot") { [weak self] in self?.setLive(false, for: id) } }
                } else {
                    extra.append { self.add(menu, "Show Live Website") { [weak self] in self?.confirmLive(id) } }
                }
            }
            extra.append {
                self.add(menu, "Copy Capture URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(c.url, forType: .string)
                }
            }
        case .image:
            extra.append { self.add(menu, item.altText == nil ? "Add Alt Text…" : "Edit Alt Text…") { [weak self] in self?.editAltText(id) } }
        default:
            break
        }
        if Easel.canBeThumbnail(item.kind) {
            if document.thumbnail == id {
                extra.append { self.add(menu, "Reset to Default Thumbnail") { [weak self] in self?.commit("Reset Thumbnail") { $0.thumbnail = nil } } }
            } else {
                extra.append { self.add(menu, "Set as Easel Thumbnail") { [weak self] in self?.commit("Set Thumbnail") { $0.thumbnail = id } } }
            }
        }
        if !extra.isEmpty {
            menu.addItem(.separator())
            for row in extra { row() }
        }
        return menu
    }

    var canPaste: Bool {
        let pb = NSPasteboard.general
        return pb.data(forType: .craEaselItems) != nil || NSImage.canInit(with: pb)
            || (pb.string(forType: .string)).flatMap(Easel.webAddress) != nil
    }

    func canvasMenu(at p: NSPoint) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add(menu, "Paste", key: "v", enabled: canPaste) { [weak self] in self?.paste(nil) }
        menu.addItem(.separator())
        let palettes = NSMenu()
        let current: Easel.Palette = document.palette == .chill ? .chill : .vibrant
        for palette in Easel.Palette.menu {
            let row = EaselMenuItem(title: palette.title) { [weak self] in
                self?.commit("Change Palette") { $0.palette = palette == .vibrant ? nil : palette }
            }
            row.state = current == palette ? .on : .off
            palettes.addItem(row)
        }
        let paletteRow = NSMenuItem(title: "Color Palette", action: nil, keyEquivalent: "")
        paletteRow.submenu = palettes
        menu.addItem(paletteRow)
        menu.addItem(.separator())
        let guidesRow = EaselMenuItem(title: "Use Alignment Guides") { Self.usesGuides.toggle() }
        guidesRow.state = Self.usesGuides ? .on : .off
        menu.addItem(guidesRow)
        return menu
    }

    static func shadeName(_ shade: Easel.Shade) -> String {
        switch shade {
        case .black: "Black"
        case .gray: "Gray"
        case .white: "White"
        case .pink: "Pink"
        case .red: "Red"
        case .yellow: "Yellow"
        case .lightGreen: "Light Green"
        case .darkGreen: "Dark Green"
        case .lightBlue: "Light Blue"
        case .darkBlue: "Dark Blue"
        case .purple: "Purple"
        }
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor(white: 0.5, alpha: 0.5).setStroke()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    /// Arc's dialog before a capture shows the live site (easel.liveWebCardEduDialogSeen: asked once).
    static let liveToldKey = "easelLiveCaptureTold"
    func confirmLive(_ id: UUID) {
        guard !UserDefaults.standard.bool(forKey: Self.liveToldKey), let window else { setLive(true, for: id); return }
        let alert = NSAlert()
        alert.messageText = "Replace this screenshot with the live website?"
        alert.informativeText = "See an up-to-date, interactive view of whatever you've captured. This does not work on all sites. You can always flip back to the screenshot from this menu."
        alert.addButton(withTitle: "Show Live Website")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(true, forKey: Self.liveToldKey)
            self?.setLive(true, for: id)
        }
    }

    /// Arc's Add Alt Text… / Edit Alt Text…: a picture's description for VoiceOver.
    func editAltText(_ id: UUID) {
        guard let window, let i = document.items.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Alt Text"
        alert.informativeText = "Describe this image for people who can't see it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = document.items[i].altText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, let i = self.document.items.firstIndex(where: { $0.id == id }) else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.commit("Edit Alt Text") { $0.items[i].altText = text.isEmpty ? nil : text }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return history.canUndo
        case #selector(redo(_:)): return history.canRedo
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)): return !picked.isEmpty
        case #selector(selectAll(_:)): return !document.items.isEmpty
        case #selector(paste(_:)): return canPaste
        default: return true
        }
    }

    /// cra://debug?easelPick=<n>: the n-th item picked, as a click picks it.
    func pick(index n: Int) -> Easel.Item? {
        guard document.items.indices.contains(n) else { return nil }
        selected = document.items[n].id
        return document.items[n]
    }

    /// cra://debug?easelDraw=1: a rectangle, an ellipse, an arrow and a stroke, each a step of its own.
    func debugDraw() {
        let y = 220.0
        for (tool, a, b) in [(Easel.Tool.rectangle, Easel.Point(120, y), Easel.Point(300, y + 120)), (.ellipse, .init(340, y), .init(500, y + 120)),
                             (.arrow, .init(540, y + 120), .init(700, y))] {
            if let item = Easel.Item.drawn(tool, from: a, to: b) { commit("Draw") { $0.items.append(item) } }
        }
        let wave = (0...20).map { Easel.Point(740 + Double($0) * 8, y + 60 + sin(Double($0) / 2) * 40) }
        if let item = Easel.freehand(wave) { commit("Draw") { $0.items.append(item) } }
    }

    // MARK: Live captures

    /// Live pages for the captures that show one, while the easel is in a window.
    func syncLives() {
        let wanted: [UUID: Easel.Capture] = window == nil ? [:] : Dictionary(uniqueKeysWithValues: document.items.compactMap { item in
            if case .capture(let c) = item.kind, c.live == true, c.canGoLive { return (item.id, c) }
            return nil
        })
        for (id, live) in lives where wanted[id] == nil {
            live.close()
            lives[id] = nil
            liveImages[id] = nil
            needsDisplay = true
        }
        for (id, capture) in wanted where lives[id] == nil {
            guard let live = EaselHooks.live?(capture, profilePath) else { continue }
            live.onFrame = { [weak self] image in
                guard let self, self.lives[id] != nil else { return }
                self.liveImages[id] = image
                self.liveFrameCount += 1
                if let item = self.item(id) { self.setNeedsDisplay(self.rect(item.frame).insetBy(dx: -2, dy: -2)) }
            }
            live.onFail = { [weak self] in
                guard let self else { return }
                self.lives[id] = nil
                self.liveImages[id] = nil
                self.needsDisplay = true
            }
            lives[id] = live
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncLives()
    }

    func closeLives() {
        for live in lives.values { live.close() }
        lives = [:]
        liveImages = [:]
    }

    /// Arc's "Replace this screenshot with the live website?" and back.
    func setLive(_ live: Bool, for id: UUID) {
        guard let i = document.items.firstIndex(where: { $0.id == id }), case .capture(var c) = document.items[i].kind else { return }
        c.live = live ? true : nil
        commit(live ? "Show Live Website" : "Show Screenshot") { $0.items[i].kind = .capture(c) }
    }

    // MARK: Copy and paste (Arc's object menu: Cut, Copy, Paste, Duplicate)

    @objc func copy(_ sender: Any?) {
        // Every picked item, bottom to top (#580).
        let items = document.items.filter { picked.contains($0.id) }
        guard let item = items.first, let data = try? JSONEncoder().encode(EaselClip(easel: document.id, items: items)) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        // Cra's own type for pasting on an easel, and what other apps can take (for one item).
        var other: [NSPasteboard.PasteboardType: Data] = [:]
        if items.count == 1 {
            switch item.kind {
            case .link(let l): other[.string] = Data(l.url.utf8); other[.URL] = Data(l.url.utf8)
            case .capture(let c): other[.png] = try? Data(contentsOf: picturesURL(c.image))
            case .image(let f): other[.png] = try? Data(contentsOf: picturesURL(f))
            case .text(let s, _): other[.string] = Data(s.utf8)
            default: break
            }
        }
        pb.declareTypes([.craEaselItems] + Array(other.keys), owner: nil)
        pb.setData(data, forType: .craEaselItems)
        for (type, value) in other { pb.setData(value, forType: type) }
    }

    @objc func cut(_ sender: Any?) {
        guard !picked.isEmpty else { return }
        copy(sender)
        deleteSelected()
    }

    @objc func delete(_ sender: Any?) { deleteSelected() }

    private func picturesURL(_ file: String) -> URL { EaselFiles.pictures(document.id).appendingPathComponent(file) }

    /// Paste: easel items copied in Cra, else a web address as a link card, else a picture.
    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .craEaselItems), let clip = try? JSONDecoder().decode(EaselClip.self, from: data) {
            pasteItems(clip)
            return
        }
        if let text = pb.string(forType: .string) ?? pb.string(forType: .URL), let url = Easel.webAddress(text) {
            addLink(url, title: nil, at: nil)
            return
        }
        guard let image = NSImage(pasteboard: pb) else { return }
        addPicture(image, at: nil)
    }

    private func pasteItems(_ clip: EaselClip) {
        // Pictures come along from the easel they were copied from.
        let from = EaselFiles.pictures(clip.easel), to = EaselFiles.pictures(document.id)
        func carry(_ file: String) -> String {
            guard clip.easel != document.id else { return file }
            let name = UUID().uuidString + "." + (file as NSString).pathExtension
            try? FileManager.default.copyItem(at: from.appendingPathComponent(file), to: to.appendingPathComponent(name))
            return name
        }
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        var pasted: [Easel.Item] = []
        // Any app can write the pasteboard: an item naming a picture by a path is left out.
        let items = clip.items.filter { Easel.files(of: $0).allSatisfy(Easel.isPlainFileName) }
        // A copy pasted where its original is shows beside it; on another easel, in view. Several
        // items keep their places among themselves (#580).
        var shift: Easel.Point?
        if let box = Easel.bounds(of: items.map(\.frame)), clip.easel != document.id || !visible.intersects(rect(box)) {
            shift = .init(visible.midX - box.width / 2 - box.x, visible.midY - box.height / 2 - box.y)
        }
        for item in items {
            var copy = Easel.copy(of: item)
            if let shift { copy = Easel.copy(of: item, offset: 0).moved(by: shift) }
            switch copy.kind {
            case .image(let f): copy.kind = .image(file: carry(f))
            case .capture(var c): c.image = carry(c.image); copy.kind = .capture(c)
            case .link(var l): l.image = l.image.map(carry); l.icon = l.icon.map(carry); copy.kind = .link(l)
            default: break
            }
            pasted.append(copy)
        }
        commit("Paste") { $0.items.append(contentsOf: pasted) }
        for item in pasted { if case .text = item.kind { addTextField(for: item) } }
        picked = pasted.map(\.id)
    }

    /// Arc's Duplicate button: a copy of each picked item, 20 pt down and right, picked.
    func duplicateSelected() {
        let items = document.items.filter { picked.contains($0.id) }
        guard !items.isEmpty else { return }
        let pics = EaselFiles.pictures(document.id)
        func clone(_ file: String) -> String {
            let name = UUID().uuidString + "." + (file as NSString).pathExtension
            try? FileManager.default.copyItem(at: pics.appendingPathComponent(file), to: pics.appendingPathComponent(name))
            return name
        }
        let copies = items.map { item in
            var copy = Easel.copy(of: item)
            switch item.kind {
            case .image(let file): copy.kind = .image(file: clone(file))
            case .capture(var c): c.image = clone(c.image); copy.kind = .capture(c)
            default: break
            }
            return copy
        }
        commit("Duplicate") { $0.items.append(contentsOf: copies) }
        for copy in copies { if case .text = copy.kind { addTextField(for: copy) } }
        picked = copies.map(\.id)
    }

    func addPictureFromFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { if let image = NSImage(contentsOf: url) { self.addPicture(image, at: nil) } }
        }
    }

    private func addPicture(_ image: NSImage, at point: NSPoint?) {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let name = UUID().uuidString + ".png"
        try? png.write(to: EaselFiles.pictures(document.id).appendingPathComponent(name))
        let scale = min(1, 420 / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        let item = Easel.Item(kind: .image(file: name), frame: .init(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                                     width: size.width, height: size.height))
        images[name] = image
        commit("Add Image") { $0.items.append(item) }
        selected = item.id
    }

    /// A link card for `url` (Arc's LinkData): placed at once, its title, text and picture filled in
    /// when the page's og: tags arrive.
    func addLink(_ url: String, title: String?, at point: NSPoint?) {
        let size = Easel.linkCardSize
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        let item = Easel.Item(kind: .link(Easel.Link(url: url, title: title)),
                              frame: .init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
        commit("Add Link") { $0.items.append(item) }
        selected = item.id
        let easel = document.id
        EaselHooks.fetchLink?(url) { [weak self] meta, picture, icon in
            // Deleted meanwhile: filling the card in would make the easel again.
            guard let self, self.document.id == easel, !EaselFiles.deleted.contains(easel),
                  let i = self.document.items.firstIndex(where: { $0.id == item.id }),
                  case .link(var link) = self.document.items[i].kind else { return }
            link.title = meta?.title ?? link.title
            link.summary = meta?.summary
            @MainActor func keep(_ data: Data?) -> String? {
                guard let data else { return nil }
                let name = UUID().uuidString + ".img"
                return (try? data.write(to: EaselFiles.pictures(easel).appendingPathComponent(name))) != nil ? name : nil
            }
            link.image = keep(picture) ?? link.image
            link.icon = keep(icon) ?? link.icon
            // Filling the card in isn't a step of its own: the step that added it covers it.
            self.document.items[i].kind = .link(link)
            self.needsDisplay = true
            self.onChange(self.document)
        }
    }

    // Pictures, image files, web addresses and sidebar tabs dropped on the canvas.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let at = convert(sender.draggingLocation, from: nil)
        let pb = sender.draggingPasteboard
        if let data = pb.data(forType: .easelSidebarRow), let tab = EaselHooks.sidebarLink?(data) {
            addLink(tab.url, title: tab.title, at: at)
            return true
        }
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] ?? []
        let pictures = urls.compactMap(NSImage.init(contentsOf:)) + (urls.isEmpty ? [NSImage(pasteboard: pb)].compactMap { $0 } : [])
        if !pictures.isEmpty {
            for image in pictures { addPicture(image, at: at) }
            return true
        }
        let web = (pb.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []).map(\.absoluteString) + [pb.string(forType: .string)].compactMap { $0 }
        if let url = web.lazy.compactMap(Easel.webAddress).first {
            addLink(url, title: nil, at: at)
            return true
        }
        return false
    }

    // MARK: Text

    /// The pill sits 20 pt left of the picked text box, level with its top (Arc: buttons 24 pt,
    /// 44 pt left of the title box).
    private func placeSizePill() {
        placeColorPicker()
        if titlePicked {
            sizePill.isHidden = false
            sizePill.frame = NSRect(x: title.frame.minX - 44, y: title.frame.minY, width: 24, height: 72)
            return
        }
        guard let id = selected, let item = document.items.first(where: { $0.id == id }), case .text = item.kind else {
            sizePill.isHidden = true
            return
        }
        sizePill.isHidden = false
        sizePill.frame = NSRect(x: item.frame.x - 44, y: item.frame.y, width: 24, height: 72)
    }

    /// The colour picker sits over the picked shapes, or the picked text, when it applies to every pick
    /// (Easel.pickerApplies; not while one is being dragged or drawn). Several show the colour they share, if they do.
    private func placeColorPicker() {
        let items = document.items.filter { picked.contains($0.id) }
        guard tool == .pointer, !items.isEmpty, Easel.pickerApplies(to: items.map(\.kind)),
              let box = Easel.bounds(of: items.map(\.frame)) else { colorPicker.isHidden = true; return }
        let shades = Set(items.map { $0.shade ?? ($0.color == nil ? Easel.defaultShade($0.kind) : nil) })
        colorPicker.palette = document.palette
        colorPicker.current = shades.count == 1 ? shades.first! : nil
        colorPicker.frame = EaselColorPicker.frame(over: rect(box))
        colorPicker.isHidden = false
    }

    /// A colour from the picker for the picked shapes and text (#658).
    func setShade(_ shade: Easel.Shade) {
        let ids = picked
        guard !ids.isEmpty else { return }
        commit("Change Color") {
            for i in $0.items.indices where ids.contains($0.items[i].id) { $0.items[i].shade = shade; $0.items[i].color = nil }
        }
        for item in document.items where ids.contains(item.id) { texts[item.id]?.textColor = textColor(of: item) }
        placeColorPicker()
    }

    /// A text's colour: its shade in the easel's palette (#658), else the canvas's white ink.
    private func textColor(of item: Easel.Item) -> NSColor {
        item.shade.map { Self.color($0, palette: document.palette, dark: Self.dark) } ?? .white
    }

    /// Scenarios (#658): the first text box picked, the picker's colour `name` applied as a click on its dot
    /// does, then "easel text color: picker=1 shade=red ink=#RRGGBB" (picker: whether it showed over the text).
    func debugTextColor(_ name: String) -> String {
        func firstText() -> Easel.Item? { document.items.first { if case .text = $0.kind { return true } else { return false } } }
        if firstText() == nil {
            let text = Easel.Item(kind: .text("Colour me", size: 24), frame: .init(x: 120, y: 420, width: 240, height: 40))
            commit("Text") { $0.items.append(text) }
            addTextField(for: text)
        }
        guard let item = firstText() else { return "no text" }
        picked = [item.id]
        selected = item.id
        placeColorPicker()
        let shown = !colorPicker.isHidden
        if let shade = Easel.Shade(rawValue: name) { setShade(shade) }
        let ink = texts[item.id]?.textColor?.usingColorSpace(.sRGB).map { c in
            String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        } ?? "-"
        let shade = document.items.first { $0.id == item.id }?.shade.map(\.rawValue) ?? "none"
        return "picker=\(shown ? 1 : 0) shade=\(shade) ink=\(ink)"
    }

    /// Arc's four looks for the Aa button (Easel.FontStyle) in macOS's own designs.
    static func font(_ style: Easel.FontStyle?, size: Double, title: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: title ? .bold : .medium)
        switch style ?? .standard {
        case .standard: return base
        case .serif:
            let regular = NSFont.systemFont(ofSize: size, weight: .regular)
            return regular.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? regular
        case .wide: return NSFont.systemFont(ofSize: size, weight: .heavy, width: .expanded)
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }

    private func cycleSelectedStyle() {
        if titlePicked {
            commit("Change Font") { $0.titleStyle = ($0.titleStyle ?? .standard).next }
            title.font = Self.font(document.titleStyle, size: document.titleSize ?? 34, title: true)
            return
        }
        guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        commit("Change Font") { $0.items[i].style = ($0.items[i].style ?? .standard).next }
        texts[id]?.font = Self.font(document.items[i].style, size: size, title: false)
        refitText(id, record: false)
    }

    private func resizeSelectedText(by step: Double) {
        if titlePicked {
            let new = min(96, max(14, (document.titleSize ?? 34) + step))
            commit("Change Text Size") { $0.titleSize = new }
            title.font = Self.font(document.titleStyle, size: new, title: true)
            return
        }
        guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }),
              case .text(let string, let size) = document.items[i].kind else { return }
        let new = min(96, max(10, size + step))
        let frame = fittedTextFrame(document.items[i], string: string, size: new)
        commit("Change Text Size") {
            $0.items[i].kind = .text(string, size: new)
            $0.items[i].frame = frame
        }
        texts[id]?.font = Self.font(document.items[i].style, size: new, title: false)
        texts[id]?.frame = rect(document.items[i].frame)
        placeSizePill()
    }

    private func addTextField(for item: Easel.Item) {
        guard case .text(let string, let size) = item.kind else { return }
        let f = EaselTextField(string: string)
        let id = item.id
        f.onFocus = { [weak self] in self?.selected = id }
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Self.font(item.style, size: size, title: false)
        f.textColor = textColor(of: item)
        f.placeholderString = "Type something"
        // Several lines that wrap in the box, as Arc's (#580).
        f.usesSingleLineMode = false
        f.cell?.wraps = true
        f.cell?.isScrollable = false
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.delegate = self
        f.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        f.frame = rect(item.frame)
        addSubview(f)
        texts[item.id] = f
    }

    /// A text box being typed in is the picked one: its size pill shows.
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        // A whole typing session is one undo step.
        history.record(document, "Typing")
        if f === title { selected = nil; titlePicked = true; return }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else { return }
        selected = id
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        var key = EaselTextKey(command: NSStringFromSelector(commandSelector))
        // The title is one line: Return ends it.
        if control === title, key == .newline { key = .finish }
        switch key {
        case .pass: return false
        case .newline:
            // A text box's Return and ⇧Return start a line (#580).
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        case .finish:
            window?.makeFirstResponder(self)
            titlePicked = false
            return true
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === title {
            commit(record: false) { $0.title = f.stringValue.isEmpty ? "Untitled Easel" : f.stringValue }
            return
        }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        // An editable field has no intrinsic width, so the box stayed 240 pt and cut the rest off (#580).
        let frame = fittedTextFrame(document.items[i], string: f.stringValue, size: size)
        commit(record: false) {
            $0.items[i].kind = .text(f.stringValue, size: size)
            $0.items[i].frame = frame
        }
        f.frame = rect(frame)
        placeSizePill()
    }

    /// `item`'s frame fitted to `string` at `size` in its font: as wide as its longest line up to Easel's
    /// widest text (#580), or the width a drag set (#680), wrapped there, and as tall as its lines.
    private func fittedTextFrame(_ item: Easel.Item, string: String, size: Double) -> Easel.Rect {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font(item.style, size: size, title: false)]
        let longest = string.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
        // A last empty line counts: it is where the caret is after Return.
        let measured = (string.isEmpty || string.hasSuffix("\n") ? string + " " : string) as NSString
        let width = Easel.textBoxWidth(item, longestLine: Double(longest))
        let bounds = NSSize(width: width - Easel.textPadding, height: .greatestFiniteMagnitude)
        let wrappedHeight = Double(measured.boundingRect(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs).height) + 4
        let height = Easel.textHeight(wrappedHeight: wrappedHeight, size: size)
        return Easel.Rect(x: item.frame.x, y: item.frame.y, width: width, height: height)
    }

    /// The text box `id` fitted to its text again, after its font changed.
    private func refitText(_ id: UUID, record: Bool) {
        guard let i = document.items.firstIndex(where: { $0.id == id }), case .text(let string, let size) = document.items[i].kind else { return }
        let frame = fittedTextFrame(document.items[i], string: string, size: size)
        guard frame != document.items[i].frame else { return }
        commit(record: record) { $0.items[i].frame = frame }
        texts[id]?.frame = rect(frame)
        placeSizePill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .pointer ? .arrow : (tool == .text ? .iBeam : .crosshair))
        // The picked item's corners: the diagonal resize cursors. A shape's or text box's edges, along their whole
        // length: left-right or up-down, as Arc shows them (a text box's top and bottom too, which move nothing, #680).
        guard tool == .pointer, let id = selected, let item = document.items.first(where: { $0.id == id }), Easel.resizes(item.kind) else { return }
        let f = rect(item.frame), g = CGFloat(Easel.cornerGrab)
        if Easel.resizesFromEdges(item.kind) {
            let tall = max(0, f.height - 2 * g), wide = max(0, f.width - 2 * g)
            addCursorRect(NSRect(x: f.minX - g, y: f.minY + g, width: 2 * g, height: tall), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: f.maxX - g, y: f.minY + g, width: 2 * g, height: tall), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: f.minX + g, y: f.minY - g, width: wide, height: 2 * g), cursor: .resizeUpDown)
            addCursorRect(NSRect(x: f.minX + g, y: f.maxY - g, width: wide, height: 2 * g), cursor: .resizeUpDown)
        }
        for (falling, x, y) in [(true, f.minX, f.minY), (false, f.maxX, f.minY), (false, f.minX, f.maxY), (true, f.maxX, f.maxY)] {
            addCursorRect(NSRect(x: x - g, y: y - g, width: 2 * g, height: 2 * g), cursor: falling == isFlipped ? Self.nwseCursor : Self.neswCursor)
        }
    }

    /// macOS's diagonal frame-resize cursors (macOS 15+), else the crosshair.
    static let nwseCursor: NSCursor = {
        if #available(macOS 15.0, *) { return NSCursor.frameResize(position: .topLeft, directions: .all) }
        return .crosshair
    }()
    static let neswCursor: NSCursor = {
        if #available(macOS 15.0, *) { return NSCursor.frameResize(position: .topRight, directions: .all) }
        return .crosshair
    }()
}

/// A text field that says when it takes the keyboard: clicking a text box picks it, and its
/// pill comes up before anything is typed.
final class EaselTextField: NSTextField {
    var onFocus: () -> Void = {}
    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { onFocus() }
        return took
    }
}

/// Arc's text-size pill (AX "add", "FontIcon", "remove", 24 pt buttons on black).
@MainActor
final class EaselSizePill: NSView {
    var onStep: (Double) -> Void = { _ in }
    var onStyle: () -> Void = {}
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [.white]))
        for (i, name) in ["plus", "textformat", "minus"].enumerated() {
            guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
            let r = NSRect(x: 0, y: CGFloat(i) * 24, width: 24, height: 24)
            img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        switch Int(y / 24) {
        case 0: onStep(4)
        case 1: onStyle()
        case 2: onStep(-4)
        default: break
        }
    }
}

/// Arc's Easel toolbar: Pointer, Image, Text, Ellipse, Rectangle, Arrow, Freehand.
@MainActor
final class EaselToolbar: NSView {
    var onPick: (Easel.Tool) -> Void = { _ in }
    /// Arc's eighth button, Duplicate (AX "Duplicate"), after the tools.
    var onDuplicate: () -> Void = {}
    var tool: Easel.Tool = .pointer { didSet { needsDisplay = true } }
    /// Arc's capture editor shows the seven tools only (#851): no Duplicate and no line before it.
    var showsDuplicate = true { didSet { needsDisplay = true } }
    private var shownItems: [EaselToolbarLayout.Item] { EaselToolbarLayout.items.filter { showsDuplicate || $0 != .duplicate } }

    private static let symbols: [Easel.Tool: String] = [
        .pointer: "cursorarrow", .image: "photo", .text: "character", .ellipse: "circle",
        .rectangle: "square", .arrow: "arrow.up.right", .freehand: "scribble",
    ]
    private static let names: [Easel.Tool: String] = [
        .pointer: "Select", .image: "Image", .text: "Text", .ellipse: "Ellipse", .rectangle: "Rectangle", .arrow: "Arrow", .freehand: "Draw",
    ]
    // Measured on a gold space: bar #100D00 (backgroundExtra), picked #716328, glyphs #FAEEC2.
    private static let bar = NSColor(srgbRed: 0.06, green: 0.05, blue: 0.0, alpha: 0.96)
    private static let picked = NSColor(white: 1, alpha: 0.22)
    private static let glyph = NSColor(white: 1, alpha: 0.92)
    // Arc 1.173.1 on a purple space (17 Nov 2026): bar #080913, picked #4E4F7F, under the
    // pointer #393A58, the line before Duplicate #20212A. Here as the same steps over Cra's bar.
    private static let hover = NSColor(white: 1, alpha: 0.145)
    private static let line = NSColor(white: 1, alpha: 0.1)

    /// The button under the pointer (Arc: a darker fill than the picked tool's, and the tool's key).
    private(set) var hovered: EaselToolbarLayout.Item? { didSet { if hovered != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Self.bar.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        if showsDuplicate {
            Self.line.setFill()
            EaselToolbarLayout.divider.fill()
        }
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold).applying(.init(paletteColors: [Self.glyph]))
        for item in shownItems {
            let r = EaselToolbarLayout.rect(of: item)
            let look = EaselToolbarLayout.look(of: item, picked: tool, hovered: hovered)
            if look.fill != .none {
                (look.fill == .picked ? Self.picked : Self.hover).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            let symbol: String, name: String?
            switch item {
            case .tool(let t): (symbol, name) = (Self.symbols[t] ?? "circle", Self.names[t])
            case .duplicate: (symbol, name) = ("square.on.square", "Duplicate")
            }
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: name)?.withSymbolConfiguration(config) {
                img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            if let hint = look.hint {
                let font = NSFont.systemFont(ofSize: EaselToolbarLayout.hintSize, weight: .bold)
                let text = NSAttributedString(string: hint, attributes: [.font: font, .foregroundColor: Self.glyph])
                let baseline = r.maxY - EaselToolbarLayout.hintBaseline
                text.draw(at: NSPoint(x: r.maxX - EaselToolbarLayout.hintTrailing - text.size().width, y: baseline - font.ascender))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        switch shownItem(at: convert(event.locationInWindow, from: nil)) {
        case .tool(let t)?: onPick(t)
        case .duplicate?: onDuplicate()
        case nil: break
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    /// The pointer at `point` (the toolbar's coordinates), or gone (nil). Also the test hook's way in.
    func hover(at point: NSPoint?) { hovered = point.flatMap { shownItem(at: $0) } }

    private func shownItem(at point: NSPoint) -> EaselToolbarLayout.Item? {
        EaselToolbarLayout.item(at: point).flatMap { shownItems.contains($0) ? $0 : nil }
    }

    /// For cra.log: the picked tool, the button under the pointer and each letter that shows.
    var debugLine: String {
        let hints = EaselToolbarLayout.items.compactMap { EaselToolbarLayout.look(of: $0, picked: tool, hovered: hovered).hint }
        let over: String = switch hovered {
        case .tool(let t)?: t.rawValue
        case .duplicate?: "duplicate"
        case nil: "none"
        }
        return "picked=\(tool.rawValue) hover=\(over) letters=\(hints.joined(separator: ","))"
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .toolbar }
    override func accessibilityLabel() -> String? { "Easel tools" }
}

extension NSColor {
    convenience init?(hexString: String) {
        guard let c = HexColor.components(hexString) else { return nil }
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

/// A menu row that runs a closure.
final class EaselMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
