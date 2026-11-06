import AppKit

final class PeekDimPanel: NSPanel {
    private final class Shade: NSView {
        var onClick: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func rightMouseDown(with event: NSEvent) { onClick() }
    }

    init(covering parent: NSWindow, onClick: @escaping () -> Void) {
        let frame = Self.coveredFrame(of: parent)
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
        shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        shade.layer?.cornerRadius = LittleWindow.cornerRadius(of: parent)
        shade.layer?.cornerCurve = .continuous
        shade.autoresizingMask = [.width, .height]
        contentView = shade
    }

    func reposition(covering parent: NSWindow) {
        setFrame(Self.coveredFrame(of: parent), display: true)
    }

    private static func coveredFrame(of parent: NSWindow) -> NSRect {
        parent.frame.insetBy(dx: 8, dy: 8)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
