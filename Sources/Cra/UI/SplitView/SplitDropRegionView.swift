import AppKit

/// The empty pane Arc opens where a dragged tab would land (`SplitViewController`'s `.dropRegion`
/// pane): a card with nothing in it, the window's backdrop showing through.
final class SplitDropRegionView: NSView {
    var isDark = false { didSet { if isDark != oldValue { refresh() } } }
    var cornerRadius: CGFloat = CraMetrics.contentCornerRadius { didSet { layer?.cornerRadius = cornerRadius } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// It never takes a click or a drop itself: the drag stays with the panes under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func refresh() {
        layer?.backgroundColor = NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.04 : 0.03).cgColor
        layer?.borderColor = NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.10 : 0.08).cgColor
    }
}
