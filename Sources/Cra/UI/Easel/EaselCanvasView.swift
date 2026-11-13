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
        // A new easel is on disk from the start, so Library ▸ Easels lists it.
        if !FileManager.default.fileExists(atPath: store.url.path) { store.saveNow(document) }
        sheet = EaselSheetView(document: document)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = sheet
        addSubview(scroll)
        addSubview(toolbar)
        sheet.onChange = { [weak self] doc in self?.changed(doc) }
        sheet.onToolDone = { [weak self] in self?.toolbar.tool = .pointer; self?.sheet.tool = .pointer }
        toolbar.onDuplicate = { [weak self] in self?.sheet.duplicateSelected() }
        toolbar.onPick = { [weak self] tool in
            guard let self else { return }
            if tool == .image { self.sheet.addPictureFromFile(); return }
            self.sheet.tool = tool
            self.toolbar.tool = tool
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func changed(_ doc: Easel) {
        let renamed = doc.title != document.title
        document = doc
        guard !EaselFiles.deleted.contains(doc.id) else { return }
        store.save(doc)
        if renamed { onTitle(doc.title) }
    }

    /// A deleted easel's tab, closing, writes nothing back.
    func saveNow() { if !EaselFiles.deleted.contains(document.id) { store.saveNow(document) } }

    func focus() { window?.makeFirstResponder(sheet) }

    /// The profile of the tab the easel is in: live captures load there.
    var profilePath: String? {
        get { sheet.profilePath }
        set { sheet.profilePath = newValue }
    }

    func closeLives() { sheet.closeLives() }

    var sheetView: EaselSheetView { sheet }


    override func layout() {
        super.layout()
        scroll.frame = bounds
        sheet.frame = NSRect(x: 0, y: 0, width: max(bounds.width - (scroll.verticalScroller?.frame.width ?? 0) * 0, 300),
                             height: Easel.canvasHeight)
        let n = CGFloat(Easel.Tool.allCases.count + 1)  // the tools, then Duplicate
        let w = 4 + n * 38 - 2 + 4
        toolbar.frame = NSRect(x: 16, y: bounds.height - 16 - 44, width: w, height: 44)
    }
}

/// The drawing itself.
@MainActor
final class EaselSheetView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    private(set) var document: Easel
    var tool: Easel.Tool = .pointer { didSet { window?.invalidateCursorRects(for: self); placeColorPicker() } }
    var onChange: (Easel) -> Void = { _ in }
    var onToolDone: () -> Void = {}
    private let title = EaselTextField()
    private var texts: [UUID: NSTextField] = [:]
    private var selected: UUID? { didSet { if selected != nil { titlePicked = false }; needsDisplay = true; placeSizePill(); window?.invalidateCursorRects(for: self) } }
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
        let w = min(CGFloat(Easel.titleWidth), bounds.width - 40)
        title.frame = NSRect(x: (bounds.width - w) / 2, y: CGFloat(Easel.titleTop) + 24, width: w, height: 48)
        for item in document.items { texts[item.id]?.frame = rect(item.frame) }
    }

    private func rect(_ r: Easel.Rect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }
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
                f.frame = rect(item.frame)
            } else {
                addTextField(for: item)
            }
        }
        if title.stringValue != easel.title, easel.title != "Untitled Easel" || !title.stringValue.isEmpty { title.stringValue = easel.title }
        title.font = Self.font(easel.titleStyle, size: easel.titleSize ?? 34, title: true)
        if let id = selected, !ids.contains(id) { selected = nil }
        placeSizePill()
        needsDisplay = true
        onChange(document)
        syncLives()
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
        if let id = selected, let item = document.items.first(where: { $0.id == id }) {
            if Easel.resizes(item.kind) {
                // Arc 1.172.1: a square 2 pt outline on the item's edge (#7FB8D6) and, at each corner,
                // a 7.5 pt ring of it round a 3 pt dark dot (8 Nov 2026, 2x stills).
                let r = rect(item.frame)
                Self.arcSelection.setStroke()
                let path = NSBezierPath(rect: r.insetBy(dx: -1, dy: -1))
                path.lineWidth = 2
                path.stroke()
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
        switch tool {
        case .pointer:
            // A corner of the picked picture or shape resizes it; anywhere else picks (and moves).
            if let item = item(selected), Easel.resizes(item.kind), let corner = Easel.corner(of: item.frame, at: p) {
                resizing = (corner, item.frame)
                return
            }
            let hit = document.item(at: p)
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
            selected = hit?.id
            if event.clickCount == 2, let hit {
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
        let p = point(event)
        guard let start = dragStart, let last = dragLast else { return }
        dragLast = p
        switch tool {
        case .pointer:
            guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }) else { return }
            if dragBefore == nil { dragBefore = document }
            if let r = resizing {
                let keep = Easel.keepsRatio(document.items[i].kind) || event.modifierFlags.contains(.shift)
                document.items[i].frame = Easel.resized(r.from, corner: r.corner, to: p, keepRatio: keep)
                needsDisplay = true
                return
            }
            // Where the drag puts it, then onto its neighbours' edges (Use Alignment Guides).
            let from = dragBefore?.items.first { $0.id == id } ?? document.items[i]
            var moved = from.moved(by: .init(p.x - start.x, p.y - start.y))
            guides = []
            if Self.usesGuides, !event.modifierFlags.contains(.command) {
                let others = document.items.filter { $0.id != id }.map(\.frame)
                let snap = Easel.snapped(moved.frame, to: others)
                moved = moved.moved(by: .init(snap.frame.x - moved.frame.x, snap.frame.y - moved.frame.y))
                guides = snap.guides
            }
            document.items[i] = moved
            _ = last
            texts[id]?.frame = rect(document.items[i].frame)
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
        defer { dragStart = nil; dragLast = nil; preview = nil; stroke = []; resizing = nil; dragBefore = nil; guides = [] }
        switch tool {
        case .pointer:
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
        if event.keyCode == 51 || event.keyCode == 117, selected != nil {  // Delete, Forward Delete
            deleteSelected()
        } else if event.keyCode == 53 {
            selected = nil
        } else {
            super.keyDown(with: event)
        }
    }

    func deleteSelected() {
        guard let id = selected else { return }
        texts.removeValue(forKey: id)?.removeFromSuperview()
        selected = nil
        commit("Delete") { $0.items.removeAll { $0.id == id } }
    }

    // MARK: Menus (Arc's EaselObjectMenuProvider and EaselCanvasMenuProvider)

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = point(event)
        if let hit = document.item(at: p) {
            selected = hit.id
            return objectMenu(for: hit)
        }
        selected = nil
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
    func objectMenu(for item: Easel.Item) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let id = item.id
        add(menu, "Bring to Front", enabled: !document.isFront(id)) { [weak self] in self?.commit("Bring to Front") { $0.bringToFront(id) } }
        add(menu, "Send to Back", enabled: !document.isBack(id)) { [weak self] in self?.commit("Send to Back") { $0.sendToBack(id) } }
        add(menu, "Delete") { [weak self] in self?.deleteSelected() }
        menu.addItem(.separator())
        add(menu, "Cut", key: "x") { [weak self] in self?.cut(nil) }
        add(menu, "Copy", key: "c") { [weak self] in self?.copy(nil) }
        add(menu, "Paste", key: "v", enabled: canPaste) { [weak self] in self?.paste(nil) }
        menu.addItem(.separator())
        add(menu, "Duplicate") { [weak self] in self?.duplicateSelected() }
        var extra: [() -> Void] = []
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
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)): return selected != nil
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
        guard let item = item(selected), let data = try? JSONEncoder().encode(EaselClip(easel: document.id, items: [item])) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        // Cra's own type for pasting on an easel, and what other apps can take.
        var other: [NSPasteboard.PasteboardType: Data] = [:]
        switch item.kind {
        case .link(let l): other[.string] = Data(l.url.utf8); other[.URL] = Data(l.url.utf8)
        case .capture(let c): other[.png] = try? Data(contentsOf: picturesURL(c.image))
        case .image(let f): other[.png] = try? Data(contentsOf: picturesURL(f))
        case .text(let s, _): other[.string] = Data(s.utf8)
        default: break
        }
        pb.declareTypes([.craEaselItems] + Array(other.keys), owner: nil)
        pb.setData(data, forType: .craEaselItems)
        for (type, value) in other { pb.setData(value, forType: type) }
    }

    @objc func cut(_ sender: Any?) {
        guard selected != nil else { return }
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
        for item in clip.items where Easel.files(of: item).allSatisfy(Easel.isPlainFileName) {
            var copy = Easel.copy(of: item)
            // A copy pasted where its original is shows beside it; on another easel, in view.
            if clip.easel != document.id || !visible.intersects(rect(item.frame)) {
                copy = Easel.copy(of: item, offset: 0).moved(by: .init(visible.midX - item.frame.width / 2 - item.frame.x,
                                                                        visible.midY - item.frame.height / 2 - item.frame.y))
            }
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
        selected = pasted.last?.id
    }

    /// Arc's Duplicate button: a copy of the picked item, 20 pt down and right, picked.
    func duplicateSelected() {
        guard let item = item(selected) else { return }
        var copy = Easel.copy(of: item)
        let pics = EaselFiles.pictures(document.id)
        func clone(_ file: String) -> String {
            let name = UUID().uuidString + "." + (file as NSString).pathExtension
            try? FileManager.default.copyItem(at: pics.appendingPathComponent(file), to: pics.appendingPathComponent(name))
            return name
        }
        switch item.kind {
        case .image(let file): copy.kind = .image(file: clone(file))
        case .capture(var c): c.image = clone(c.image); copy.kind = .capture(c)
        default: break
        }
        commit("Duplicate") { $0.items.append(copy) }
        if case .text = copy.kind { addTextField(for: copy) }
        selected = copy.id
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
            guard let self, self.document.id == easel, let i = self.document.items.firstIndex(where: { $0.id == item.id }),
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

    /// The colour picker sits over the picked shape (not while it is being dragged or drawn).
    private func placeColorPicker() {
        guard tool == .pointer, let item = item(selected), Easel.takesShade(item.kind) else { colorPicker.isHidden = true; return }
        colorPicker.palette = document.palette
        colorPicker.current = item.shade ?? (item.color == nil ? Easel.defaultShade(item.kind) : nil)
        colorPicker.frame = EaselColorPicker.frame(over: rect(item.frame))
        colorPicker.isHidden = false
    }

    /// A colour from the picker for the picked shape.
    func setShade(_ shade: Easel.Shade) {
        guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }) else { return }
        commit("Change Color") { $0.items[i].shade = shade; $0.items[i].color = nil }
        placeColorPicker()
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
        let height = ceil(new * 1.45)
        commit("Change Text Size") {
            $0.items[i].kind = .text(string, size: new)
            $0.items[i].frame.height = height
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
        f.textColor = .white
        f.placeholderString = "Type something"
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
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        window?.makeFirstResponder(self)
        titlePicked = false
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === title {
            commit(record: false) { $0.title = f.stringValue.isEmpty ? "Untitled Easel" : f.stringValue }
            return
        }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        let width = max(240, ceil(f.intrinsicContentSize.width) + 8)
        commit(record: false) {
            $0.items[i].kind = .text(f.stringValue, size: size)
            $0.items[i].frame.width = width
        }
        f.frame.size.width = width
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .pointer ? .arrow : (tool == .text ? .iBeam : .crosshair))
        // The picked picture's or shape's corners: the diagonal resize cursors.
        guard tool == .pointer, let id = selected, let item = document.items.first(where: { $0.id == id }), Easel.resizes(item.kind) else { return }
        let f = item.frame, g = Easel.cornerGrab
        for (corner, x, y) in [(Easel.Corner.topLeft, f.x, f.y), (.topRight, f.x + f.width, f.y),
                               (.bottomLeft, f.x, f.y + f.height), (.bottomRight, f.x + f.width, f.y + f.height)] {
            let falling = corner == .topLeft || corner == .bottomRight
            addCursorRect(NSRect(x: x - g, y: y - g, width: 2 * g, height: 2 * g), cursor: falling ? Self.nwseCursor : Self.neswCursor)
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

    override var isFlipped: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    private func buttonRect(_ i: Int) -> NSRect { NSRect(x: 4 + CGFloat(i) * 38, y: 4, width: 36, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        Self.bar.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        for (i, t) in Easel.Tool.allCases.enumerated() {
            let r = buttonRect(i)
            if t == tool {
                Self.picked.setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold).applying(.init(paletteColors: [Self.glyph]))
            guard let img = NSImage(systemSymbolName: Self.symbols[t] ?? "circle", accessibilityDescription: Self.names[t])?
                .withSymbolConfiguration(config) else { continue }
            img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        let dr = buttonRect(Easel.Tool.allCases.count)
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold).applying(.init(paletteColors: [Self.glyph]))
        if let img = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Duplicate")?.withSymbolConfiguration(config) {
            img.draw(in: NSRect(x: dr.midX - img.size.width / 2, y: dr.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, t) in Easel.Tool.allCases.enumerated() where buttonRect(i).contains(p) { onPick(t) }
        if buttonRect(Easel.Tool.allCases.count).contains(p) { onDuplicate() }
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
