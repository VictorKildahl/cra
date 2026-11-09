import AppKit

/// Covers a browser window's page area while a Peek shows on it; a click on it ends the Peek. It
/// leaves the window's edge band uncovered (PeekLayout.dismissArea), so a press there resizes the
/// window and the Peek stays, as in Arc, where the Peek is a card inside the window, and the
/// sidebar, whose rows open their tabs while the Peek waits on its own (#242).
final class PeekDimPanel: NSPanel {
    private final class Shade: NSView {
        var onClick: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func rightMouseDown(with event: NSEvent) { onClick() }
    }

    init(covering area: NSRect, of parent: NSWindow, onClick: @escaping () -> Void) {
        super.init(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let shade = Shade(frame: NSRect(origin: .zero, size: area.size))
        shade.onClick = onClick
        shade.wantsLayer = true
        // The page fades instead (MainWindowController.showPeekVeil); this only catches the click,
        // and a window passes clicks through where it is fully clear.
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        shade.layer?.cornerRadius = LittleWindow.cornerRadius(of: parent)
        shade.layer?.cornerCurve = .continuous
        shade.autoresizingMask = [.width, .height]
        contentView = shade
        roundCorners(of: parent)
    }

    /// Follows the browser window as it moves or resizes under the Peek, and its sidebar.
    func reposition(covering area: NSRect, of parent: NSWindow) {
        if frame != area { setFrame(area, display: true) }
        roundCorners(of: parent)
    }

    /// Only the corners on the window's own edge are rounded; beside the sidebar it is straight.
    private func roundCorners(of parent: NSWindow) {
        let besideSidebar = frame.minX > parent.frame.minX + PeekLayout.dismissInset + 0.5
        contentView?.layer?.maskedCorners = besideSidebar ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
