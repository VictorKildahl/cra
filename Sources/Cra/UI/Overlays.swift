import AppKit
import Observation

/// Overlay state shown on top of the web content: link status, find bar.
@MainActor
@Observable
final class OverlayState {
    var status = ""
    var findVisible = false
    var findQuery = "" {
        didSet {
            guard findQuery != oldValue else { return }
            findMatchCount = nil
            findActiveMatch = 0
            onFindQueryChange?(findQuery)
        }
    }
    /// Synchronous, so Return cannot use a previous query while Observation is pending.
    var onFindQueryChange: ((String) -> Void)?
    var findFocusToken = 0
    /// Find in page results ("2/7" in the bar); nil until the page answers.
    var findMatchCount: Int?
    var findActiveMatch = 0
}

/// The link under the pointer, bottom left over the page, as Arc's link preview (#689): a black
/// capsule with the address in dim 12 pt text, and while ⇧, ⌥ or ⌘ is held what a click will do
/// ("Open <address> in Peek"), the address bright (LinkPreview). AppKit: it changes on every link
/// the pointer crosses.
final class StatusBubbleView: NSView {
    /// Measured on the reporter's Arc screenshots (2x): 24 pt tall, 1 pt border at white 20 % on
    /// black, 12 pt medium text 10 pt in from each end, dim text at 175/255 and the address white.
    static let height: CGFloat = 24
    static let padding: CGFloat = 10
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// Opaque: the capsule is opaque black, and white at 69 % drew twice came out at 230.
    static let dim = NSColor(srgbRed: 175.0 / 255, green: 175.0 / 255, blue: 175.0 / 255, alpha: 1)
    static let bright = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private let overlay: OverlayState
    private let bubble = NSView()
    private let label = NSTextField.sidebarLabel(size: 12, weight: .medium)
    /// Settings ▸ Links' Shift-click Peek for this window's pages; false in incognito (no Peek).
    var peekOnShiftClick: () -> Bool = { true }
    private var modifiers: NSEvent.ModifierFlags = []
    private var flagsMonitor: Any?
    private(set) var text = LinkPreview.Text(lead: "", emphasis: "", trail: "")

    init(overlay: OverlayState) {
        self.overlay = overlay
        super.init(frame: .zero)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.black.cgColor
        bubble.layer?.cornerRadius = Self.height / 2
        bubble.layer?.cornerCurve = .continuous
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(bubble)
        addSubview(label)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func observe() {
        let status = withObservationTracking { overlay.status } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // The keys held as the pointer comes onto a link, then each change while it is shown.
        if !status.isEmpty, flagsMonitor == nil {
            modifiers = NSEvent.modifierFlags
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                self?.modifiers = e.modifierFlags
                self?.render()
                return e
            }
        } else if status.isEmpty, let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        render()
    }

    private func render() {
        let status = overlay.status
        text = LinkPreview.text(status, modifiers: modifiers.rawValue, peekOnShiftClick: peekOnShiftClick())
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let shown = NSMutableAttributedString()
        for (part, color) in [(text.lead, Self.dim), (text.emphasis, Self.bright), (text.trail, Self.dim)] where !part.isEmpty {
            shown.append(NSAttributedString(string: part, attributes: [.font: Self.font, .foregroundColor: color, .paragraphStyle: paragraph]))
        }
        label.attributedStringValue = shown
        bubble.isHidden = status.isEmpty
        label.isHidden = status.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let s = label.attributedStringValue.size()
        let w = min(ceil(s.width) + 2 * Self.padding, max(0, bounds.width - 12))
        let h = Self.height
        bubble.frame = NSRect(x: 6, y: 6, width: w, height: h)
        let th = ceil(s.height)
        label.frame = NSRect(x: 6 + Self.padding - SidebarText.inset, y: 6 + (h - th) / 2,
                             width: max(0, w - 2 * Self.padding) + 2 * SidebarText.inset, height: th)
    }

    /// For scenarios (#689): what the preview shows, its parts and its capsule.
    func readout(_ label: String) -> String {
        let shown = !bubble.isHidden && !overlay.status.isEmpty
        return "Cra link preview \(label): shown=\(shown ? "yes" : "no") text=\(text.string) bright=\(text.emphasis.isEmpty ? "-" : text.emphasis)"
            + " height=\(Int(bubble.frame.height)) radius=\(Int(bubble.layer?.cornerRadius ?? 0)) fill=\(bubble.layer?.backgroundColor == NSColor.black.cgColor ? "black" : "other")"
    }
}

/// Find in page, top trailing over the page: glyph, field, "2/7", previous, next, close.
final class FindBarView: NSView, NSTextFieldDelegate {
    private let overlay: OverlayState
    private let onFind: (String, Bool) -> Void   // query, forward
    private let onClose: () -> Void
    private let card = MaterialCardView(radius: 10)
    private let glyph = NSImageView()
    private let field = NSTextField()
    private let count = NSTextField.sidebarLabel(size: 11)
    private var buttons: [ClosureButton] = []
    private var lastFocusToken = 0
    private var wasVisible = false

    init(overlay: OverlayState, onFind: @escaping (String, Bool) -> Void, onClose: @escaping () -> Void) {
        self.overlay = overlay
        self.onFind = onFind
        self.onClose = onClose
        super.init(frame: .zero)
        addSubview(card)
        glyph.image = SidebarSymbols.image("magnifyingglass", size: 13)
        glyph.contentTintColor = .secondaryLabelColor
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Find in page"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        addSubview(count)
        for (symbol, run) in [("chevron.up", { [weak self] in self.map { $0.onFind($0.overlay.findQuery, false) } }),
                              ("chevron.down", { [weak self] in self.map { $0.onFind($0.overlay.findQuery, true) } }),
                              ("xmark", { [weak self] in self?.onClose() })] as [(String, () -> Void)] {
            let b = ClosureButton(symbol: symbol, size: 13, onPress: run)
            buttons.append(b)
            addSubview(b)
        }
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func observe() {
        let (visible, query, matches, active, token) = withObservationTracking {
            (overlay.findVisible, overlay.findQuery, overlay.findMatchCount, overlay.findActiveMatch, overlay.findFocusToken)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        for v in subviews { v.isHidden = !visible }
        if field.stringValue != query { field.stringValue = query }
        if let matches, !query.isEmpty {
            count.stringValue = "\(matches == 0 ? 0 : active)/\(matches)"
            count.isHidden = !visible
        } else {
            count.stringValue = ""
            count.isHidden = true
        }
        // Ask on Page's card stands in for the bar while its setting is on: its field takes the keys.
        if visible, !isHidden, !wasVisible || token != lastFocusToken { window?.makeFirstResponder(field) }
        wasVisible = visible
        lastFocusToken = token
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if overlay.findVisible, !isHidden { window?.makeFirstResponder(field) }
    }

    func controlTextDidChange(_ obj: Notification) {
        overlay.findQuery = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onFind(overlay.findQuery, !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose()
            return true
        default:
            return false
        }
    }

    override func layout() {
        super.layout()
        card.frame = bounds
        let h = bounds.height
        // padding 10, glyph, 6, field (flexible), 6, count, 6, ▲, 6, ▼, 6, ✕, padding 10.
        var x = bounds.width - 10
        for b in buttons.reversed() {
            let s = b.image?.size ?? .zero
            b.frame = NSRect(x: x - s.width, y: (h - s.height) / 2, width: s.width, height: s.height)
            x -= s.width + 6
        }
        if !count.isHidden {
            let w = ceil(count.attributedStringValue.size().width)
            count.frame = NSRect(x: x - w - SidebarText.inset, y: (h - 14) / 2, width: w + 2 * SidebarText.inset, height: 14)
            x -= w + 6
        }
        let gw = glyph.image?.size.width ?? 14
        glyph.frame = NSRect(x: 10, y: 0, width: gw, height: h)
        let fx = 10 + gw + 6
        let fh = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: fx - SidebarText.inset, y: (h - fh) / 2, width: max(0, x - fx + 2 * SidebarText.inset), height: fh)
    }
}

/// The find bar's own window, just the bar's size, over the page windows. The
/// page-sized overlay panel can't take key and would swallow every click on the page.
final class FindBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: CraMetrics.findBarSize),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
    }
}
