import AppKit
import SwiftUI

/// Arc's hover tips for small controls (ArcTooltip, PresentationBehavior.onMouseIdle).
/// Measured on Arc 1.170's sidebar row buttons (27 Oct 2026, 1x screen recordings): the tip
/// shows once the pointer has rested ~1.6 s, at once when moving from another tip, pops in
/// without a fade, fades out in ~60 ms, and hangs off the bottom-trailing corner of a 16 pt
/// box around the glyph. Clicking the control dismisses it.
@MainActor
final class ArcTooltipController {
    static let shared = ArcTooltipController()

    static let idleDelay: TimeInterval = 1.6
    /// Moving onto another control this soon after a tip closed shows its tip right away.
    static let warmWindow: TimeInterval = 0.5

    private var panel: LittleTooltipPanel?
    private weak var shownFor: (any ArcTooltipTarget)?
    private weak var pendingFor: (any ArcTooltipTarget)?
    private var timer: Timer?
    private var lastHiddenAt = Date.distantPast
    private var clickMonitor: Any?
    private var flagsMonitor: Any?
    /// Anchors under the pointer; a row and its close button both track it, and the
    /// innermost (smallest) one owns the tip (Arc: TooltipController.enteredViewStack).
    private var hovered: [WeakAnchor] = []

    private struct WeakAnchor { weak var view: (any ArcTooltipTarget)? }

    /// Set while a list scrolls under the pointer: no tip shows or starts waiting, and the
    /// next one waits for the pointer to rest the full delay.
    var paused = false { didSet { if paused { dismiss() } } }

    /// The tones of the space a window is in (AppDelegate). Arc paints every tip in a browser
    /// window from that space's palette, whichever control or space icon it belongs to; windows
    /// without a space (Little Windows) get nil and Little Arc's navy.
    var tones: (NSWindow) -> TooltipTones? = { _ in nil }

    private init() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            self?.dismiss()
            return e
        }
        // Modifier keys keep the tip up (Arc: allowedModifierKeys); ⌥ swaps in the option text.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            if let self, let v = self.shownFor, v.optionText != nil { self.show(for: v) }
            return e
        }
    }

    func mouseMoved(in view: any ArcTooltipTarget) {
        if !hovered.contains(where: { $0.view === view }) { hovered.append(WeakAnchor(view: view)) }
        let mouse = NSEvent.mouseLocation
        hovered.removeAll { a in
            guard let v = a.view, v.hostWindow != nil else { return true }
            return !v.screenFrame.contains(mouse)
        }
        guard let target = hovered.compactMap(\.view).min(by: { $0.screenFrame.width * $0.screenFrame.height < $1.screenFrame.width * $1.screenFrame.height }),
              !target.text.isEmpty else {
            if shownFor != nil { hide() }
            cancelPending()
            return
        }
        if shownFor === target || paused { return }
        startTip(for: target)
    }

    private func startTip(for view: any ArcTooltipTarget) {
        if panel != nil || Date().timeIntervalSince(lastHiddenAt) < Self.warmWindow {
            show(for: view)
            return
        }
        // On mouse idle: every move restarts the wait.
        pendingFor = view
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: view.idleDelay, repeats: false) { [weak self, weak view] _ in
            Task { @MainActor in
                guard let self, let view, self.pendingFor === view, !self.paused else { return }
                self.show(for: view)
            }
        }
    }

    func mouseExited(_ view: any ArcTooltipTarget) {
        hovered.removeAll { $0.view === view || $0.view == nil }
        if pendingFor === view { cancelPending() }
        if shownFor === view { hide() }
        // Leaving a close button for the rest of its row hands the tip back to the row.
        if let outer = hovered.last?.view, outer.hostWindow != nil { mouseMoved(in: outer) }
    }

    /// A click or key press: the next tip waits for the pointer to rest again, so a row that
    /// slides under the pointer after the click doesn't pop its tip.
    func dismiss() {
        cancelPending()
        hide()
        lastHiddenAt = .distantPast
    }

    private func cancelPending() {
        timer?.invalidate()
        timer = nil
        pendingFor = nil
    }

    /// Testing: the tip for `help` over a rect of `view`, without a pointer.
    func debugShow(_ help: String, in view: NSView, at rect: NSRect) {
        let a = ArcTooltipAnchorView(frame: rect)
        (a.text, a.keys) = ArcTooltipLabel.split(help)
        view.addSubview(a)
        show(for: a)
    }

    /// Testing: the tip of the n-th space icon (1-based, left to right) in the dock under `view`,
    /// or with 0 the Library button's.
    func debugShowSpaceTip(_ n: Int, in view: NSView) {
        func all<T: NSView>(_ v: NSView, _ t: T.Type) -> [T] { v.subviews.flatMap { ($0 as? T).map { [$0] } ?? all($0, t) } }
        if n == 0, let library = all(view, LibraryButtonView.self).first,
           let tip = all(library, ArcTooltipAnchorView.self).first(where: { $0.placement == .trailing }) {
            show(for: tip)
            return
        }
        let cells = all(view, SpaceCellView.self).filter { $0.window != nil }.sorted { $0.screenFrame.minX < $1.screenFrame.minX }
        guard n >= 1, n <= cells.count else { return }
        show(for: cells[n - 1])
    }

    private func show(for view: any ArcTooltipTarget) {
        cancelPending()
        guard let window = view.hostWindow, !view.text.isEmpty else { return }
        removePanel()
        let p = LittleTooltipPanel()
        let option = NSEvent.modifierFlags.contains(.option) ? view.optionText : nil
        let colors = tones(window).map(ArcTooltipLabel.Colors.init) ?? .little
        let label = ArcTooltipLabel(text: option ?? view.text, keys: option == nil ? view.keys : [],
                                    subtitle: option == nil ? view.subtitle : nil, badge: option == nil ? view.badge : nil,
                                    colors: colors)
        let size = label.frame.size
        p.contentView = label
        // Buttons: off the bottom-trailing corner of a 16 pt box around the glyph.
        // Rows: Arc's .cursor anchor, 13 pt right of and 14 pt below the pointer.
        // Space icons: centred, its bottom 19.75 pt above the icon's centre. The Library button:
        // 19.5 pt right of its centre, centred on it (Arc 1.171, 2x, 3 Nov 2026).
        let r = view.screenFrame
        let mouse = NSEvent.mouseLocation
        var origin: NSPoint
        switch view.placement {
        case .above: origin = NSPoint(x: r.midX - size.width / 2, y: r.midY + 19.75)
        case .trailing: origin = NSPoint(x: r.midX + 19.5, y: r.midY - size.height / 2)
        case .corner:
            let anchor = view.followsCursor ? NSPoint(x: mouse.x + 13, y: mouse.y - 14) : NSPoint(x: r.midX + 8, y: r.midY - 7)
            origin = NSPoint(x: anchor.x, y: anchor.y - size.height)
        }
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            if origin.y < screen.minY + 4 { origin.y = (view.followsCursor ? mouse.y : r.midY) + 7 }
        }
        p.setFrame(NSRect(origin: origin, size: size), display: true)
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        shownFor = view
        view.onShow?()
    }

    private func hide() {
        guard let p = panel else { return }
        panel = nil
        shownFor = nil
        lastHiddenAt = Date()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.06
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        })
    }

    private func removePanel() {
        guard let p = panel else { return }
        panel = nil
        shownFor = nil
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }
}

/// What a tip belongs to: an AppKit control's anchor view, or a SwiftUI view's hover.
@MainActor
protocol ArcTooltipTarget: AnyObject {
    var text: String { get }
    var keys: [String] { get }
    var followsCursor: Bool { get }
    var subtitle: String? { get }
    var optionText: String? { get }
    var onShow: (() -> Void)? { get }
    var screenFrame: NSRect { get }
    var hostWindow: NSWindow? { get }
    /// A profile pill after the text (Arc's space icons).
    var badge: String? { get }
    /// How long the pointer rests before the tip shows.
    var idleDelay: TimeInterval { get }
    var placement: ArcTooltipPlacement { get }
}

extension ArcTooltipTarget {
    var badge: String? { nil }
    var idleDelay: TimeInterval { ArcTooltipController.idleDelay }
    var placement: ArcTooltipPlacement { .corner }
}

/// Where a control's tip goes (Arc: ArcTooltipConfiguration.preferredAnchor).
enum ArcTooltipPlacement {
    /// Off the bottom-trailing corner, or by the pointer for `followsCursor`.
    case corner
    /// Centred above (the dock's space icons).
    case above
    /// Beside it, centred (the dock's Library button).
    case trailing
}

/// Tracks the pointer over an AppKit control without taking its clicks.
final class ArcTooltipAnchorView: NSView, ArcTooltipTarget {
    var text = ""
    var keys: [String] = []
    var followsCursor = false
    /// A second, dimmer line (Arc's SidebarCellTooltipView subtitle, e.g. "Double-click to rename").
    var subtitle: String?
    /// Shown instead while ⌥ is held (the split close button un-splits on ⌥-click).
    var optionText: String?
    var onShow: (() -> Void)?
    var placement = ArcTooltipPlacement.corner

    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }

    /// For AppKit controls: an anchor filling `control`.
    static func attach(to control: NSView, help: String) -> ArcTooltipAnchorView {
        let a = ArcTooltipAnchorView(frame: control.bounds)
        a.autoresizingMask = [.width, .height]
        (a.text, a.keys) = ArcTooltipLabel.split(help)
        control.addSubview(a)
        return a
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        // activeAlways: the key window is usually a Chromium page window, not the sidebar's.
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        // Rebuilt under the pointer (its control moved): no mouseEntered comes, so only this gets the mouseExited.
        if let w = window, visibleRect.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { ArcTooltipController.shared.mouseMoved(in: self) } }
    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { ArcTooltipController.shared.mouseMoved(in: self) } }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { ArcTooltipController.shared.mouseExited(self) } }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Row buttons vanish when the row loses hover; their tip goes with them.
        if newWindow == nil { MainActor.assumeIsolated { ArcTooltipController.shared.mouseExited(self) } }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// A SwiftUI view's tip, fed by its hover. No AppKit view per tip: the sidebar has hundreds of
/// rows and buttons across its spaces, and an anchor view in each one had SwiftUI move every
/// one of them, AppKit redo their tracking areas and rebuild its key view loop on every frame
/// of a space swipe or sidebar scroll.
@MainActor
private final class ArcTooltipSource: ArcTooltipTarget {
    var text = ""
    var keys: [String] = []
    var followsCursor = false
    var subtitle: String?
    var optionText: String?
    var onShow: (() -> Void)?
    var size = CGSize.zero
    /// The view's frame on screen, worked out from the last hover: the pointer's screen
    /// position and its position in the view.
    private(set) var screenFrame = NSRect.zero
    private(set) weak var hostWindow: NSWindow?

    /// Called on every pointer move. The window under the pointer is a window server query,
    /// so it is looked up once per visit (`entered`), not per move.
    func hovered(at local: CGPoint, entered: Bool) {
        let mouse = NSEvent.mouseLocation
        // SwiftUI's local y grows downwards, the screen's upwards.
        screenFrame = NSRect(x: mouse.x - local.x, y: mouse.y + local.y - size.height, width: size.width, height: size.height)
        if entered || hostWindow == nil {
            hostWindow = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0))
        }
    }

    /// Between the pointer arriving and leaving.
    var isHovered = false
}

private struct ArcTooltipModifier: ViewModifier {
    let text: String
    let keys: [String]
    let followsCursor: Bool
    let subtitle: String?
    let optionText: String?
    let onShow: (() -> Void)?
    @State private var source = ArcTooltipSource()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { source.size = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    source.text = text
                    source.keys = keys
                    source.followsCursor = followsCursor
                    source.subtitle = subtitle
                    source.optionText = optionText
                    source.onShow = onShow
                    source.hovered(at: location, entered: !source.isHovered)
                    source.isHovered = true
                    ArcTooltipController.shared.mouseMoved(in: source)
                case .ended:
                    source.isHovered = false
                    ArcTooltipController.shared.mouseExited(source)
                }
            }
            // Row buttons vanish when the row loses hover; their tip goes with them.
            .onDisappear { ArcTooltipController.shared.mouseExited(source) }
    }
}

extension View {
    /// Arc-style tooltip. A trailing shortcut in parentheses, "Close Tab (⌘W)", becomes key caps.
    /// `followsCursor` places it by the pointer (Arc's sidebar rows and tiles) instead of the control.
    func arcTooltip(_ help: String, followsCursor: Bool = false, subtitle: String? = nil,
                    optionHelp: String? = nil, onShow: (() -> Void)? = nil) -> some View {
        let (text, keys) = ArcTooltipLabel.split(help)
        return modifier(ArcTooltipModifier(text: text, keys: keys, followsCursor: followsCursor, subtitle: subtitle,
                                           optionText: optionHelp, onShow: onShow))
    }
}

/// The tip itself: 28 pt capsule in the window's space tones with a one-pixel ring of white at
/// 10 %, 12 pt medium text, then 19 pt key caps 6 pt on, 3 pt apart and 10 pt from the end: a face
/// inset 1 pt on the sides and top and 2.5 pt at the bottom, over the darker edge (Arc 1.171, 2x
/// captures of "View Library ⇧⌘L" and the space icons; Little Arc's larger tip is LittleTooltip).
/// A space icon's tip adds its profile in a pill between the text and the caps.
final class ArcTooltipLabel: NSView {
    static let maxTextWidth: CGFloat = 280
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let cap: CGFloat = 19
    private static let capGap: CGFloat = 3
    private static let textToCaps: CGFloat = 6
    private static let capsTrailing: CGFloat = 10

    struct Colors {
        var fill, title, cap, capGlyph, capEdge: NSColor

        init(fill: NSColor, title: NSColor, cap: NSColor, capGlyph: NSColor, capEdge: NSColor) {
            (self.fill, self.title, self.cap, self.capGlyph, self.capEdge) = (fill, title, cap, capGlyph, capEdge)
        }

        init(_ t: TooltipTones) {
            self.init(fill: NSColor(t.fill), title: NSColor(t.title), cap: NSColor(t.badge), capGlyph: NSColor(t.ink),
                      capEdge: NSColor(t.badge.mixed(with: t.ink, 0.5)))
        }

        /// Little Arc's tip, whatever space is focused.
        static let little = Colors(fill: NSColor(LittlePalette.tooltip), title: NSColor(LittlePalette.tooltipText),
                                   cap: NSColor(LittlePalette.tooltipCap), capGlyph: NSColor(LittlePalette.tooltipCapGlyph),
                                   capEdge: NSColor(red: 119 / 255, green: 122 / 255, blue: 211 / 255, alpha: 1))
    }

    static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private let title = NSTextField(wrappingLabelWithString: "")
    private let sub = NSTextField.sidebarLabel(size: 11)
    private var caps: [NSView] = []
    private var pill: ProfilePill?
    private let multiline: Bool

    init(text: String, keys: [String], subtitle: String? = nil, badge: String? = nil, colors: Colors = .little) {
        let wraps = Self.width(of: text) > Self.maxTextWidth
        multiline = wraps || subtitle != nil
        super.init(frame: .zero)
        wantsLayer = true
        // Two or more lines get a rounded rectangle (Cra's choice; Arc's multi-line tip wasn't observed).
        layer?.backgroundColor = colors.fill.cgColor
        layer?.borderColor = colors.fill.blended(withFraction: 0.1, of: .white)?.cgColor
        layer?.cornerRadius = multiline ? 10 : 14
        title.font = Self.font
        title.textColor = colors.title
        title.stringValue = text
        // Long titles wrap at a fixed width (ArcTooltipConfiguration.maxWidth; Arc's value is unknown).
        title.maximumNumberOfLines = wraps ? 3 : 1
        title.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        title.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        if let subtitle {
            sub.stringValue = subtitle
            sub.textColor = colors.title.withAlphaComponent(0.6)
            addSubview(sub)
        }
        if let badge, !multiline {
            let p = ProfilePill(name: badge, fill: colors.cap, ink: colors.capGlyph)
            pill = p
            addSubview(p)
        }
        for k in keys {
            let edge = NSView()
            edge.wantsLayer = true
            edge.layer?.backgroundColor = colors.capEdge.cgColor
            edge.layer?.cornerRadius = 4.5
            edge.layer?.cornerCurve = .continuous
            let face = NSView(frame: NSRect(x: 1, y: 2.5, width: Self.cap - 2, height: Self.cap - 3.5))
            face.wantsLayer = true
            face.layer?.backgroundColor = colors.cap.cgColor
            face.layer?.cornerRadius = 3.5
            face.layer?.cornerCurve = .continuous
            edge.addSubview(face)
            let glyph = NSTextField.sidebarLabel(size: 10, weight: .bold)
            glyph.stringValue = k
            glyph.textColor = colors.capGlyph
            glyph.alignment = .center
            glyph.frame = NSRect(x: -SidebarText.inset, y: (face.frame.height - 13) / 2, width: face.frame.width + 2 * SidebarText.inset, height: 13)
            face.addSubview(glyph)
            caps.append(edge)
            addSubview(edge)
        }
        layoutContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    }

    private var titleSize: NSSize {
        let w = multiline && title.maximumNumberOfLines > 1 ? Self.maxTextWidth : ceil(Self.width(of: title.stringValue))
        let h = title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w + 2 * SidebarText.inset, height: 1000)).height ?? 15
        return NSSize(width: w, height: ceil(h))
    }

    /// Lays the label out and sizes the view to fit (SwiftUI's .fixedSize()).
    private func layoutContent() {
        let ts = titleSize
        let subSize = sub.superview == nil ? .zero : NSSize(width: ceil(sub.attributedStringValue.size().width), height: 14)
        let textW = max(ts.width, subSize.width)
        let textH = ts.height + (sub.superview == nil ? 0 : 1 + subSize.height)
        let keysW = caps.isEmpty ? 0 : CGFloat(caps.count) * Self.cap + CGFloat(caps.count - 1) * Self.capGap
        let pillW = pill.map { ProfilePill.gap + $0.frame.width } ?? 0
        let contentH = max(textH, caps.isEmpty ? 0 : Self.cap)
        let h = max(28, contentH + (multiline ? 12 : 0))
        let trailing: CGFloat = !caps.isEmpty ? Self.capsTrailing : pill != nil ? ProfilePill.trailing : 10
        let w = 10 + textW + pillW + (caps.isEmpty ? 0 : Self.textToCaps + keysW) + trailing
        setFrameSize(NSSize(width: ceil(w), height: ceil(h)))
        // VStack(spacing: 1), centred.
        let top = (h + textH) / 2
        title.frame = NSRect(x: 10 - SidebarText.inset, y: top - ts.height, width: ts.width + 2 * SidebarText.inset, height: ts.height)
        sub.frame = NSRect(x: 10 - SidebarText.inset, y: top - ts.height - 1 - subSize.height, width: subSize.width + 2 * SidebarText.inset, height: subSize.height)
        var x = 10 + textW
        if let pill {
            pill.setFrameOrigin(NSPoint(x: x + ProfilePill.gap, y: (h - pill.frame.height) / 2))
            x += pillW
        }
        x += Self.textToCaps
        for c in caps {
            c.frame = NSRect(x: x, y: (h - Self.cap) / 2, width: Self.cap, height: Self.cap)
            x += Self.cap + Self.capGap
        }
    }

    /// "Copy URL (⇧⌘C)" → ("Copy URL", ["⇧", "⌘", "C"]).
    static func split(_ help: String) -> (String, [String]) {
        guard help.hasSuffix(")"), let open = help.range(of: " (", options: .backwards) else { return (help, []) }
        let shortcut = String(help[open.upperBound..<help.index(before: help.endIndex)])
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        guard let first = shortcut.first, modifiers.contains(first), shortcut.count <= 6 else { return (help, []) }
        var caps = shortcut.prefix { modifiers.contains($0) }.map(String.init)
        let key = shortcut.drop { modifiers.contains($0) }
        if !key.isEmpty { caps.append(String(key)) }
        return (String(help[..<open.lowerBound]), caps)
    }
}

/// The profile in a space icon's tip (Arc's tooltip on SidebarDock items): a pill of the caps'
/// colour holding a smiley avatar and the profile's name, both in the caps' glyph colour. The
/// smiley is the same for every profile: it marks the pill as a
/// profile, it isn't the profile's icon. Arc 1.171, 2x captures of "Personal [Default] ⌃1" and
/// "Work [Work] ⌃2" (3 Nov 2026): pill 22 pt tall, 6 pt from the space's name and from the caps,
/// avatar 6 pt in, then the name in 11 pt medium (a size smaller than the tip's text) 3 pt on and
/// 6 pt from the pill's end. A Default-profile space says "Default".
final class ProfilePill: NSView {
    static let height: CGFloat = 22
    static let avatar: CGFloat = 14
    /// From the space's name to the pill.
    static let gap: CGFloat = 6
    /// From the pill to the tip's end when no caps follow (the pill's inset from the capsule).
    static let trailing: CGFloat = 3
    private static let leading: CGFloat = 6
    private static let nameGap: CGFloat = 3
    private static let nameTrailing: CGFloat = 6
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    init(name: String, fill: NSColor, ink: NSColor) {
        let font = Self.font
        let label = NSTextField.sidebarLabel(size: font.pointSize)
        label.font = font
        label.stringValue = name
        label.textColor = ink
        label.lineBreakMode = .byClipping
        let textW = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        let w = Self.leading + Self.avatar + Self.nameGap + textW + Self.nameTrailing
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: Self.height))
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = Self.height / 2
        let face = ProfileAvatarView(frame: NSRect(x: Self.leading, y: (Self.height - Self.avatar) / 2, width: Self.avatar, height: Self.avatar))
        face.ink = ink
        addSubview(face)
        let th = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Self.leading + Self.avatar + Self.nameGap - SidebarText.inset, y: (Self.height - th) / 2,
                             width: textW + 2 * SidebarText.inset, height: th)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Arc's 14 pt profile smiley (ARC_ProfilesUI "archie", a template image): a disc of the ink at
/// 10 %, two upright eyes and a smile at full ink. Redrawn from the image's 2x pixels.
final class ProfileAvatarView: NSView {
    var ink = NSColor.black { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let k = bounds.width / 14
        ink.withAlphaComponent(26 / 255).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        ink.setFill()
        for x in [4.5, 8.0] {
            NSBezierPath(roundedRect: NSRect(x: x * k, y: 3 * k, width: 1.5 * k, height: 4 * k), xRadius: 0.75 * k, yRadius: 0.75 * k).fill()
        }
        // Fitted to the image's alpha at 1x and 2x (RMS 1.7/255): a quadratic, control point (7, 11.2).
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 4.1 * k, y: 9.6 * k))
        smile.curve(to: NSPoint(x: 9.9 * k, y: 9.6 * k), controlPoint1: NSPoint(x: 6.03 * k, y: 10.67 * k),
                    controlPoint2: NSPoint(x: 7.97 * k, y: 10.67 * k))
        smile.lineWidth = 1.35 * k
        smile.lineCapStyle = .round
        ink.setStroke()
        smile.stroke()
    }
}
