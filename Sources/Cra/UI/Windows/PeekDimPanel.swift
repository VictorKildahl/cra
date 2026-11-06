import AppKit

/// Covers a browser window while a Peek shows on it; a click on it ends the Peek. It leaves the
/// window's edge band uncovered (PeekLayout.dismissArea), so a press there resizes the window
/// and the Peek stays, as in Arc, where the Peek is a card inside the window.
final class PeekDimPanel: NSPanel {
    private final class Shade: NSView {
        var onClick: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func rightMouseDown(with event: NSEvent) { onClick() }
    }

    init(covering parent: NSWindow, onClick: @escaping () -> Void) {
        let frame = PeekLayout.dismissArea(covering: parent.frame)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let shade = Shade(frame: NSRect(origin: .zero, size: frame.size))
        shade.onClick = onClick
        shade.wantsLayer = true
        // The page fades instead (MainWindowController.showPeekVeil); this only catches the click,
        // and a window passes clicks through where it is fully clear.
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        shade.layer?.cornerRadius = LittleWindow.cornerRadius(of: parent)
        shade.layer?.cornerCurve = .continuous
        shade.autoresizingMask = [.width, .height]
        contentView = shade
    }

    /// Follows the browser window as it moves or resizes under the Peek.
    func reposition(covering parent: NSWindow) {
        setFrame(PeekLayout.dismissArea(covering: parent.frame), display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
