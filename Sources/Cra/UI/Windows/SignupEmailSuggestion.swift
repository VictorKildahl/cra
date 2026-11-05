import AppKit
import SwiftUI

/// The address is drawn by Cra. The page keeps the insertion point until the user picks it.
@MainActor
final class SignupEmailSuggestion: NSObject {
    private let panel = SignupSuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                              backing: .buffered, defer: false)
    private let row = SignupSuggestionButton()
    private var accept: (() -> Void)?

    var isVisible: Bool { panel.isVisible && panel.parent != nil }

    override init() {
        super.init()
        panel.title = "Email suggestion"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        let surface = NSView()
        surface.addSubview(row)
        panel.contentView = surface
        row.target = self
        row.action = #selector(pick)
    }

    /// The caller supplies the field in the coordinate space of the visible page view.
    func show(address: String, fieldRect: NSRect, in view: NSView, accept: @escaping () -> Void) {
        dismiss()
        guard !address.isEmpty, !view.isHiddenOrHasHiddenAncestor, let owner = view.window,
              owner.isVisible, let screen = owner.screen, view.visibleRect.intersects(fieldRect) else { return }
        let field = owner.convertToScreen(view.convert(fieldRect, to: nil))
        let visible = owner.convertToScreen(view.convert(view.visibleRect, to: nil))
        let area = screen.visibleFrame.intersection(visible)
        let height = SignupEmailPreview.height, gap: CGFloat = 4
        let width = min(area.width, SignupEmailPreview.width(for: address))
        guard area.intersects(field), width >= 135, area.height >= height else { return }
        let below = field.minY - gap - height
        let above = field.maxY + gap
        guard below >= area.minY || above + height <= area.maxY else { return }
        let origin = NSPoint(x: min(max(field.minX, area.minX), area.maxX - width),
                             y: below >= area.minY ? below : above)
        self.accept = accept
        row.setAddress(address)
        panel.appearance = owner.effectiveAppearance
        panel.level = owner.level
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        row.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        owner.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.didResignKeyNotification] {
            center.addObserver(self, selector: #selector(ownerChanged), name: name, object: owner)
        }
        center.addObserver(self, selector: #selector(ownerChanged), name: NSApplication.didResignActiveNotification, object: NSApp)
    }

    func setSelected(_ selected: Bool) { row.keyboardSelected = selected }

    @discardableResult
    func acceptIfShown() -> Bool {
        guard isVisible, let accept else { return false }
        dismiss()
        accept()
        return true
    }

    @objc private func pick() { acceptIfShown() }
    @objc private func ownerChanged(_ note: Notification) { dismiss() }

    func dismiss() {
        NotificationCenter.default.removeObserver(self)
        accept = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        row.setAddress("")
    }
}

private final class SignupSuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Settings shows the same surface as the popup, including the key the page handles next.
struct SignupEmailPreview: View {
    let address: String
    var keyboardSelected = false
    var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    static let height: CGFloat = 48
    static func width(for address: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textWidth = (address as NSString).size(withAttributes: [.font: font]).width
        return min(400, max(220, ceil(textWidth) + 100))
    }

    private var glyphColor: Color {
        scheme == .dark ? Color(red: 0.76, green: 0.73, blue: 1) : Color(red: 0.35, green: 0.28, blue: 0.67)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let secondary: Color = keyboardSelected ? .white.opacity(0.9) : Color(nsColor: .secondaryLabelColor)
        HStack(spacing: 0) {
            Image(systemName: "at")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(keyboardSelected ? .white : glyphColor)
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(keyboardSelected ? Color.white.opacity(0.16) : glyphColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: address)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(keyboardSelected ? .white : Color(nsColor: .labelColor))
                    .lineLimit(1).truncationMode(.middle)
                Text("Signup email")
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
            }
            .padding(.leading, 9)
            Spacer(minLength: 8)
            Image(systemName: keyboardSelected ? "return" : "arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondary)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(secondary.opacity(0.34), lineWidth: 0.75))
        }
        .padding(.horizontal, 11)
        .frame(idealWidth: Self.width(for: address), maxWidth: Self.width(for: address))
        .frame(height: Self.height)
        .background {
            if keyboardSelected {
                shape.fill(Color(red: 0.32, green: 0.27, blue: 0.60))
            } else {
                shape.fill(.regularMaterial)
                shape.fill((scheme == .dark ? Color.white : Color.black).opacity(hovered ? 0.075 : 0))
            }
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signup email preview, \(address)")
    }
}

private final class SignupSuggestionButton: NSButton {
    var keyboardSelected = false { didSet { render() } }
    private var hovered = false { didSet { render() } }
    private var address = ""
    private let content = NSHostingView(rootView: SignupEmailPreview(address: ""))

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        content.setAccessibilityElement(false)
        addSubview(content)
        setAccessibilityChildren([])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("CraSignupEmailSuggestion")
    }

    required init?(coder: NSCoder) { nil }

    func setAddress(_ address: String) {
        self.address = address
        setAccessibilityLabel(address.isEmpty ? nil : "Use \(address)")
        hovered = false
        keyboardSelected = false
    }

    private func render() {
        content.rootView = SignupEmailPreview(address: address, keyboardSelected: keyboardSelected, hovered: hovered)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, window?.isVisible == true, let action else { return false }
        return sendAction(action, to: target)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
}
