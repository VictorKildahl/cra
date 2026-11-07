import AppKit
import UniformTypeIdentifiers

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
        store.save(doc)
        if renamed { onTitle(doc.title) }
    }

    func saveNow() { store.saveNow(document) }

    func focus() { window?.makeFirstResponder(sheet) }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        sheet.frame = NSRect(x: 0, y: 0, width: max(bounds.width - (scroll.verticalScroller?.frame.width ?? 0) * 0, 300),
                             height: Easel.canvasHeight)
        let n = CGFloat(Easel.Tool.allCases.count)
        let w = 4 + n * 38 - 2 + 4
        toolbar.frame = NSRect(x: 16, y: bounds.height - 16 - 44, width: w, height: 44)
    }
}

/// The drawing itself.
@MainActor
final class EaselSheetView: NSView, NSTextFieldDelegate {
    private(set) var document: Easel
    var tool: Easel.Tool = .pointer { didSet { window?.invalidateCursorRects(for: self) } }
    var onChange: (Easel) -> Void = { _ in }
    var onToolDone: () -> Void = {}
    private let title = NSTextField()
    private var texts: [UUID: NSTextField] = [:]
    private var selected: UUID? { didSet { needsDisplay = true } }
    private var dragStart: Easel.Point?
    private var dragLast: Easel.Point?
    private var preview: Easel.Item?
    private var stroke: [Easel.Point] = []
    private var images: [String: NSImage] = [:]

    static let ink = NSColor(white: 1, alpha: 0.92)
    static let selection = NSColor(srgbRed: 0.47, green: 0.71, blue: 0.95, alpha: 1)

    init(document: Easel) {
        self.document = document
        super.init(frame: .zero)
        title.stringValue = document.title
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.alignment = .center
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        title.placeholderString = "Untitled Easel"
        title.delegate = self
        addSubview(title)
        for item in document.items { if case .text = item.kind { addTextField(for: item) } }
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The window moves by its background: a drag here draws instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let w = min(CGFloat(Easel.titleWidth), bounds.width - 40)
        title.frame = NSRect(x: (bounds.width - w) / 2, y: CGFloat(Easel.titleTop) + 24, width: w, height: 48)
        for item in document.items { texts[item.id]?.frame = rect(item.frame) }
    }

    private func rect(_ r: Easel.Rect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }
    private func point(_ e: NSEvent) -> Easel.Point { let p = convert(e.locationInWindow, from: nil); return .init(p.x, p.y) }

    private func commit(_ change: (inout Easel) -> Void) {
        change(&document)
        needsDisplay = true
        onChange(document)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for item in document.items + [preview].compactMap({ $0 }) { draw(item) }
        if stroke.count > 1, let s = Easel.freehand(stroke) { draw(s) }
        if let id = selected, let item = document.items.first(where: { $0.id == id }) {
            let r = rect(item.frame).insetBy(dx: -4, dy: -4)
            Self.selection.setStroke()
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func draw(_ item: Easel.Item) {
        let color = item.color.flatMap { NSColor(hexString: $0) } ?? Self.ink
        color.setStroke()
        let r = rect(item.frame)
        switch item.kind {
        case .rectangle:
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4); p.lineWidth = 3; p.stroke()
        case .ellipse:
            let p = NSBezierPath(ovalIn: r); p.lineWidth = 3; p.stroke()
        case .arrow(let a, let b):
            let p = NSBezierPath()
            p.move(to: NSPoint(x: a.x, y: a.y)); p.line(to: NSPoint(x: b.x, y: b.y))
            let angle = atan2(b.y - a.y, b.x - a.x), head = 16.0
            for side in [-0.5, 0.5] {
                p.move(to: NSPoint(x: b.x, y: b.y))
                p.line(to: NSPoint(x: b.x - head * cos(angle + side), y: b.y - head * sin(angle + side)))
            }
            p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .freehand(let pts):
            guard let first = pts.first else { return }
            let p = NSBezierPath()
            p.move(to: NSPoint(x: first.x, y: first.y))
            for q in pts.dropFirst() { p.line(to: NSPoint(x: q.x, y: q.y)) }
            p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .image(let file):
            let image = images[file] ?? NSImage(contentsOf: EaselFiles.pictures(document.id).appendingPathComponent(file))
            images[file] = image
            image?.draw(in: r)
        case .text:
            break  // a text field of its own
        }
    }

    // MARK: Tools

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        dragStart = p
        dragLast = p
        switch tool {
        case .pointer:
            selected = document.item(at: p)?.id
        case .text:
            let item = Easel.Item(kind: .text("", size: 18), frame: .init(x: p.x, y: p.y - 12, width: 240, height: 26))
            commit { $0.items.append(item) }
            addTextField(for: item)
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
            document.items[i] = document.items[i].moved(by: .init(p.x - last.x, p.y - last.y))
            texts[id]?.frame = rect(document.items[i].frame)
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
        defer { dragStart = nil; dragLast = nil; preview = nil; stroke = [] }
        switch tool {
        case .pointer:
            if selected != nil { onChange(document) }
        case .freehand:
            if stroke.count > 1, let item = Easel.freehand(stroke) { commit { $0.items.append(item) }; selected = nil }
        default:
            if let item = preview, item.frame.width + item.frame.height > 6 {
                commit { $0.items.append(item) }
                selected = item.id
                onToolDone()
            }
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, let id = selected {  // Delete, Forward Delete
            texts.removeValue(forKey: id)?.removeFromSuperview()
            selected = nil
            commit { $0.items.removeAll { $0.id == id } }
        } else if event.keyCode == 53 {
            selected = nil
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general) else { return }
        addPicture(image, at: nil)
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
        commit { $0.items.append(item) }
        selected = item.id
    }

    // Pictures and image files dropped on the canvas.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let at = convert(sender.draggingLocation, from: nil)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] ?? []
        let pictures = urls.compactMap(NSImage.init(contentsOf:)) + (urls.isEmpty ? [NSImage(pasteboard: sender.draggingPasteboard)].compactMap { $0 } : [])
        for image in pictures { addPicture(image, at: at) }
        return !pictures.isEmpty
    }

    // MARK: Text

    private func addTextField(for item: Easel.Item) {
        guard case .text(let string, let size) = item.kind else { return }
        let f = NSTextField(string: string)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: size, weight: .medium)
        f.textColor = .white
        f.placeholderString = "Type something"
        f.delegate = self
        f.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        f.frame = rect(item.frame)
        addSubview(f)
        texts[item.id] = f
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === title {
            commit { $0.title = f.stringValue.isEmpty ? "Untitled Easel" : f.stringValue }
            return
        }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        let width = max(240, ceil(f.intrinsicContentSize.width) + 8)
        commit {
            $0.items[i].kind = .text(f.stringValue, size: size)
            $0.items[i].frame.width = width
        }
        f.frame.size.width = width
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .pointer ? .arrow : (tool == .text ? .iBeam : .crosshair))
    }
}

/// Arc's Easel toolbar: Pointer, Image, Text, Ellipse, Rectangle, Arrow, Freehand.
@MainActor
final class EaselToolbar: NSView {
    var onPick: (Easel.Tool) -> Void = { _ in }
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
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, t) in Easel.Tool.allCases.enumerated() where buttonRect(i).contains(p) { onPick(t) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .toolbar }
    override func accessibilityLabel() -> String? { "Easel tools" }
}

private extension NSColor {
    convenience init?(hexString: String) {
        guard let c = HexColor.components(hexString) else { return nil }
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}
