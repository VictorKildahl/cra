import AppKit
import SwiftUI

/// Arc's dialog card (measured against Arc 1.172.1's Quit and Delete Space sheets, 7 Nov 2026: #161C2F).
enum DialogTheme {
    static let card = Color(hex: "#161C2F")
    static let body = Color(hex: "#B8B9C4")
}

/// The card a dialog draws on. The sheet it sits in already has macOS's 1 pt light edge, as Arc's does,
/// so the card draws none of its own.
struct DialogSurface: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(DialogTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

struct DialogButton: View {
    enum Style {
        case secondary, primary, accent, destructive

        /// Arc 1.172.1's Quit sheet under the pointer: 10 % white over Cancel (#302F60 → #454470, its key
        /// badge too), 10 % black over Quit (#3339F1 → #2D33D9).
        var hoverTint: Color { self == .secondary ? .white : .black }
    }
    let title: String
    let key: String
    let enabled: Bool
    let style: Style
    var badge: CGSize?
    let action: () -> Void
    @State private var hovered = false

    init(title: String, key: String, enabled: Bool, primary: Bool, action: @escaping () -> Void) {
        self.init(title: title, key: key, enabled: enabled, style: primary ? .primary : .secondary, action: action)
    }

    init(title: String, key: String, enabled: Bool, style: Style, badge: CGSize? = nil, action: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.enabled = enabled
        self.style = style
        self.badge = badge
        self.action = action
    }

    // Destructive (Delete in Arc's Delete Space and Delete Live Folder sheets): fill #E2492C, no lighter rim,
    // key badge #E55B41 edged #E86D56 as captured; the hex values here render to those on Cra's sheets.
    private var accent: Bool { style == .accent && enabled }
    private var destructive: Bool { style == .destructive && enabled }
    private var primary: Bool { style != .secondary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent || destructive ? .white : enabled ? Color(hex: "#EBEBEF") : Color(hex: "#5B5C7F"))
                if !key.isEmpty {
                    Text(key).font(.system(size: key == "↩" ? 13 : 11, weight: .bold))
                        .foregroundStyle(destructive ? .white : accent ? Color(hex: "#EDEDFF") : enabled ? Color(hex: "#B7B7DD") : Color(hex: "#5F6193"))
                        .frame(minWidth: badge?.width ?? 27, maxWidth: badge?.width, minHeight: badge?.height ?? 19, maxHeight: badge?.height)
                        .padding(.horizontal, badge != nil || key == "↩" ? 0 : 2)
                        .background(RoundedRectangle(cornerRadius: badge == nil ? 5 : 3, style: .continuous)
                            .fill(destructive ? Color(hex: "#F74C31") : accent ? Color(hex: "#464DFB") : primary ? Color(hex: enabled ? "#4E4C9A" : "#222469") : Color(hex: "#4E4C77")))
                        .overlay(RoundedRectangle(cornerRadius: badge == nil ? 5 : 3, style: .continuous)
                            .strokeBorder(destructive ? Color(hex: "#FA624C") : accent ? Color(hex: "#6B71FE") : .clear, lineWidth: 1))
                }
            }
            .padding(.leading, 12.5)
            .padding(.trailing, 12)
            .frame(height: 37)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(destructive ? Color(hex: "#F53516") : accent ? Color(hex: "#3239FB") : primary ? Color(hex: enabled ? "#3B3C8F" : "#1C1D4C") : Color(hex: "#302F60"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(destructive ? Color(hex: "#F53516") : accent ? Color(hex: "#5B61FD") : primary ? (enabled ? Color(hex: "#6362A9") : .clear) : Color(hex: "#6362A9"), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // Arc's default buttons sit on a darker lip, ~1.5 pt below: blue for Quit and Save, a dark
                    // red for Delete (#41232A in Arc 1.172.1's Delete Space sheet).
                    .fill(style == .accent ? Color(hex: enabled ? "#2C3475" : "#1D2259") : destructive ? Color(hex: "#41232A") : .clear)
                    .offset(y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.hoverTint.opacity(hovered && enabled ? 0.1 : 0))
                .allowsHitTesting(false))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .accessibilityLabel(title)
        .fixedSize()
    }
}

struct DialogScrollContent<Content: View>: NSViewRepresentable {
    let width: CGFloat
    let maximumHeight: CGFloat
    let content: () -> Content

    init(width: CGFloat, maximumHeight: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.maximumHeight = maximumHeight
        self.content = content
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = NSHostingView(rootView: AnyView(content().frame(width: width, alignment: .leading)))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(content().frame(width: width, alignment: .leading))
        resize(scroll)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        resize(scroll)
    }

    @discardableResult
    private func resize(_ scroll: NSScrollView) -> CGSize {
        guard let host = scroll.documentView else { return .zero }
        let height = host.fittingSize.height
        host.setFrameSize(NSSize(width: width, height: height))
        scroll.hasVerticalScroller = height > maximumHeight
        scroll.contentView.scroll(to: NSPoint(x: 0, y: host.isFlipped ? 0 : max(0, height - maximumHeight)))
        return CGSize(width: width, height: min(height, maximumHeight))
    }
}

final class DialogPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var handleKey: ((NSEvent) -> Bool)?
    private weak var owner: NSWindow?
    private var parentObserver: NSObjectProtocol?
    private(set) var isDismissing = false
    private var isClosed = false

    override var canBecomeKey: Bool { true }

    convenience init<Content: View>(over parent: NSWindow?, content: Content) {
        self.init(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        let host = NSHostingView(rootView: content)
        contentView = host
        setContentSize(host.fittingSize)
        owner = parent
        if let parent {
            parentObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        } else {
            center()
        }
    }

    func show() {
        if let owner {
            owner.beginSheet(self) { [weak self] _ in self?.finishClose() }
        } else {
            makeKeyAndOrderFront(nil)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func close() {
        guard !isClosed, !isDismissing else { return }
        isDismissing = true
        if let parent = sheetParent {
            parent.endSheet(self)
        } else {
            finishClose()
        }
    }

    private func finishClose() {
        guard !isClosed else { return }
        isClosed = true
        let dismissed = onDismiss
        onDismiss = nil
        handleKey = nil
        if let parentObserver { NotificationCenter.default.removeObserver(parentObserver) }
        parentObserver = nil
        orderOut(nil)
        super.close()
        dismissed?()
    }

    @discardableResult
    static func present<Content: View>(over parent: NSWindow, _ content: (@escaping () -> Void) -> Content) -> Bool {
        guard parent.attachedSheet == nil else { return false }
        var panel: DialogPanel?
        let window = DialogPanel(over: parent, content: content { panel?.close() })
        panel = window
        window.onDismiss = { panel = nil }
        window.show()
        return true
    }
}
