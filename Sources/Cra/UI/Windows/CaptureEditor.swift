import AppKit

/// Arc's image editor for a capture (Capture ▸ Edit, `EaselUI.ModalImageEditor`; #851), measured live on Arc 1.174:
/// the page goes dark under a black veil and the capture shows in a card in the middle, a point per pixel, with
/// Easel's seven tools at its bottom left (CaptureEditorLayout). Shapes, arrows, text, pictures and drawing go on it
/// as on an easel. A click on the dark page around the card puts the drawing into the capture and closes the editor;
/// Escape leaves it open, as in Arc.
@MainActor
final class CaptureEditorView: NSView, CaptureEditing {
    private let image: CGImage
    private let card = FlippedCardView()
    private let picture = CALayer()
    let sheet: EaselSheetView
    let toolbar = EaselToolbar()
    private let easelID: UUID
    /// The editor closed: the capture with what was drawn on it, at the capture's own pixels.
    var onDone: (CGImage) -> Void = { _ in }
    private var done = false

    init(frame: NSRect, image: CGImage) {
        self.image = image
        let document = Easel(title: "")
        easelID = document.id
        sheet = EaselSheetView(document: document)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: CaptureEditorLayout.veil).cgColor
        card.wantsLayer = true
        card.layer?.cornerRadius = CaptureEditorLayout.cornerRadius
        card.layer?.masksToBounds = true
        picture.contents = image
        picture.contentsGravity = .resize
        card.layer?.addSublayer(picture)
        sheet.editsImage = true
        card.addSubview(sheet)
        toolbar.showsDuplicate = false
        card.addSubview(toolbar)
        addSubview(card)
        sheet.onToolDone = { [weak self] in self?.toolbar.tool = .pointer; self?.sheet.tool = .pointer }
        let pick: (Easel.Tool) -> Void = { [weak self] tool in
            guard let self else { return }
            if tool == .image { self.sheet.addPictureFromFile(); return }
            self.sheet.tool = tool
            self.toolbar.tool = tool
        }
        toolbar.onPick = pick
        sheet.onToolKey = pick
        setAccessibilityLabel("Edit Capture")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var cardFrame: NSRect { card.frame }

    override func layout() {
        super.layout()
        let c = CaptureEditorLayout.card(pixels: CGSize(width: image.width, height: image.height), in: bounds.size)
        card.frame = c
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = card.bounds
        CATransaction.commit()
        sheet.frame = card.bounds
        toolbar.frame = CaptureEditorLayout.toolbar(in: c.size)
    }

    /// The sheet takes the keys, so a tool's letter picks it.
    func focus() { window?.makeFirstResponder(sheet) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(p) { finish() }
    }

    // Escape, and keys the sheet doesn't take, stay in the editor rather than ending the capture.
    override func keyDown(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}

    /// Puts the drawing into the capture and closes (the click on the dark page, or the test hook).
    func finish() {
        guard !done else { return }
        done = true
        sheet.clearPicks()
        let edited = sheet.document.items.isEmpty ? image : (flattened() ?? image)
        sheet.closeLives()
        removeFromSuperview()
        // Pictures added with the Image tool were kept beside a throwaway easel: its own folder, and nothing else.
        let pictures = EaselFiles.pictures(easelID)
        if pictures.lastPathComponent == easelID.uuidString { try? FileManager.default.removeItem(at: pictures) }
        onDone(edited)
    }

    /// The capture with the sheet drawn over it, at the capture's pixels.
    private func flattened() -> CGImage? {
        let w = image.width, h = image.height
        guard sheet.bounds.width > 0, sheet.bounds.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = sheet.bounds.size
        sheet.cacheDisplay(in: sheet.bounds, to: rep)
        guard let drawing = rep.cgImage, let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let all = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(image, in: all)
        ctx.draw(drawing, in: all)
        return ctx.makeImage()
    }
}

private final class FlippedCardView: NSView {
    override var isFlipped: Bool { true }
}
