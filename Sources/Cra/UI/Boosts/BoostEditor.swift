import AppKit
import SwiftUI

/// Arc's Boost editor (Arc 1.172.1, captured 7 Nov 2026; docs/screenshots/arc-boost-*.png): a
/// 183 × 588 pt floating panel 10 pt in from the window's right edge and 215 pt down. Header: a grey
/// ✕ (Done), "My Boost ⌄" (Rename this Boost…, Shuffle, Reset all Edits, Delete this Boost, All
/// Boosts…), Undo. Then a 147 pt colour wheel, three 42 × 38 buttons (Invert lightness, Advanced
/// colour controls: Contrast, Brightness, Original Saturation; Reset to original colours), a white
/// card of 20 "Aa" fonts, Size and Case, Zap ⚡ and Code {} (which widens the panel to 480 pt with a
/// CSS / JS switch). Every change shows on the page at once.
@MainActor
final class BoostEditorController {
    static let shared = BoostEditorController()
    private var panel: NSPanel?
    private var model: BoostEditorModel?

    func open(_ boost: Boost, over window: NSWindow, zap: @escaping (Bool) -> Void) {
        close()
        let m = BoostEditorModel(boost: boost)
        m.zap = zap
        m.onClose = { [weak self] in self?.close() }
        m.onWidth = { [weak self] w in self?.resize(width: w) }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.becomesKeyOnlyIfNeeded = true
        let host = FirstClickHostingView(rootView: BoostEditorView(model: m))
        host.sizingOptions = []
        p.contentView = host
        let f = window.frame
        p.setFrame(NSRect(x: f.maxX - 10 - 183, y: f.maxY - 215 - 588, width: 183, height: 588), display: false)
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        model = m
    }

    func close() {
        model?.finishZap()
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
        model = nil
    }

    var isOpen: Bool { panel != nil }

    /// What Zap hid, into the boost being edited.
    func addZapped(_ selectors: [String]) {
        CraLog.note("zap kept \(selectors.count) selector\(selectors.count == 1 ? "" : "s")")
        guard let model, !selectors.isEmpty else { return }
        model.change { b in b.zapped += selectors.filter { !b.zapped.contains($0) } }
    }

    private func resize(width: CGFloat) {
        guard let panel else { return }
        var f = panel.frame
        f.origin.x = f.maxX - width
        f.size.width = width
        panel.setFrame(f, display: true, animate: true)
    }
}

@MainActor
@Observable
final class BoostEditorModel {
    var boost: Boost { didSet { if boost != oldValue { BoostStore.shared.update(boost) } } }
    var history: [Boost] = []
    var showingCode = false
    var codeIsJS = false
    var zapping = false
    @ObservationIgnored var zap: (Bool) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onWidth: (CGFloat) -> Void = { _ in }

    init(boost: Boost) { self.boost = boost }

    /// One step of the editor, undoable.
    func change(_ edit: (inout Boost) -> Void) {
        history.append(boost)
        var b = boost
        edit(&b)
        boost = b
    }

    func undo() { if let last = history.popLast() { boost = last } }

    func shuffle() {
        change {
            $0.hue = Double.random(in: 0..<1)
            $0.strength = Double.random(in: 0.3...0.8)
            $0.font = Int.random(in: 0..<Boost.fonts.count)
        }
    }

    func resetAll() {
        change { b in
            let fresh = Boost(id: b.id, host: b.host, name: b.name)
            b = fresh
        }
    }

    func toggleZap() {
        zapping.toggle()
        zap(zapping)
    }

    func finishZap() { if zapping { zapping = false; zap(false) } }

    func setCode(_ on: Bool) {
        showingCode = on
        onWidth(on ? 480 : 183)
    }
}

private enum BoostStyle {
    static let panel = Color(red: 0.976, green: 0.976, blue: 0.984)
    static let button = Color(red: 0.91, green: 0.91, blue: 0.925)
    static let ink = Color(white: 0.2)
    static let secondary = Color(white: 0.55)
}

private struct BoostEditorView: View {
    @Bindable var model: BoostEditorModel
    @State private var showColors = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if model.showingCode { code } else { controls }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BoostStyle.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 0) {
            if model.showingCode {
                Button { model.setCode(false) } label: {
                    Label("Back", systemImage: "arrow.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(BoostStyle.ink).padding(.leading, 10)
                Spacer()
                Picker("", selection: $model.codeIsJS) {
                    Text("CSS").tag(false)
                    Text("JS").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 92)
                Spacer()
            } else {
                Button { model.onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Color(white: 0.6))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain).help("Done")
                Spacer(minLength: 0)
            }
            Menu {
                Button("Rename this Boost…") { rename() }
                Button("Shuffle") { model.shuffle() }
                Button("Reset all Edits") { model.resetAll() }
                Button("Delete this Boost") { delete() }
                Divider()
                Button("All Boosts…") { NotificationCenter.default.post(name: .craShowBoostsLibrary, object: nil) }
            } label: {
                HStack(spacing: 4) {
                    Text(model.boost.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(BoostStyle.ink).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(BoostStyle.ink)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Spacer(minLength: 0)
            Button { model.undo() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).foregroundStyle(model.history.isEmpty ? Color(white: 0.75) : BoostStyle.ink).disabled(model.history.isEmpty).help("Undo")
        }
        .frame(height: 40)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ColorWheel(hue: model.boost.hue, strength: model.boost.strength) { h, s in
                model.change { $0.hue = h; $0.strength = s }
            }
            .frame(width: 147, height: 147)
            .padding(.top, 18)
            HStack(spacing: 10) {
                square("lightbulb", on: model.boost.invert, help: "Invert lightness") { model.change { $0.invert.toggle() } }
                square("slider.horizontal.3", on: showColors, help: "Advanced color controls") { showColors.toggle() }
                    .popover(isPresented: $showColors, arrowEdge: .leading) { advanced }
                square("nosign", on: false, help: "Reset to original colors") {
                    model.change { $0.hue = 0; $0.strength = 0; $0.invert = false; $0.contrast = 50; $0.brightness = 50; $0.saturation = 50 }
                }
                .opacity(model.boost.colorsUntouched ? 0.45 : 1)
            }
            fonts
            HStack(spacing: 9) {
                Menu {
                    ForEach([0.8, 0.9, 1, 1.1, 1.25, 1.5], id: \.self) { s in
                        Button(s == 1 ? "Original" : "\(Int(s * 100)) %") { model.change { $0.textScale = s } }
                    }
                } label: { wide("Size", trailing: nil) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Change text size")
                Menu {
                    ForEach(Boost.TextCase.allCases, id: \.self) { c in Button(c.title) { model.change { $0.textCase = c } } }
                } label: { wide("Case", trailing: nil) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Change text case")
            }
            .frame(width: 147)
            Button { model.toggleZap() } label: { wide("Zap", trailing: "bolt.fill", on: model.zapping) }.buttonStyle(.plain)
                .help("Click things on the page to hide them")
            Button { model.setCode(true) } label: { wide("Code", trailing: "curlybraces") }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(width: 183)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider("Contrast", \.contrast)
            slider("Brightness", \.brightness)
            slider("Original Saturation", \.saturation)
        }
        .padding(18)
        .frame(width: 250)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<Boost, Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium))
            Slider(value: Binding(get: { model.boost[keyPath: key] }, set: { v in model.change { $0[keyPath: key] = v } }), in: 0...100)
        }
    }

    private var fonts: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 1.5), count: 5)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Boost.fonts.indices, id: \.self) { i in
                Button { model.change { $0.font = $0.font == i ? nil : i } } label: {
                    Text("Aa").font(.custom(Boost.fonts[i] == "-apple-system" ? "Helvetica Neue" : Boost.fonts[i], size: 13))
                        .foregroundStyle(model.boost.font == i ? Color.accentColor : BoostStyle.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 5)
        .frame(width: 147)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white).shadow(color: .black.opacity(0.08), radius: 4, y: 1))
    }

    private func square(_ symbol: String, on: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15))
                .foregroundStyle(on ? .white : BoostStyle.ink)
                .frame(width: 42, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? BoostStyle.ink : BoostStyle.button))
        }
        .buttonStyle(.plain).help(help)
    }

    private func wide(_ title: String, trailing: String?, on: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            if let trailing { Spacer(); Image(systemName: trailing).font(.system(size: 13, weight: .semibold)) }
        }
        .foregroundStyle(on ? .white : BoostStyle.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: trailing == nil ? .infinity : 147, minHeight: 38)
        .frame(width: trailing == nil ? nil : 147)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? BoostStyle.ink : BoostStyle.button))
    }

    private var code: some View {
        VStack(spacing: 0) {
            CodeEditor(text: Binding(get: { model.codeIsJS ? model.boost.js : model.boost.css },
                                     set: { v in if model.codeIsJS { model.boost.js = v } else { model.boost.css = v } }))
            HStack { Spacer() }.frame(height: 60).background(BoostStyle.panel)
        }
        .frame(width: 480)
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = "Rename this Boost"
        let field = NSTextField(string: model.boost.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { model.change { $0.name = field.stringValue } }
    }

    private func delete() {
        let alert = NSAlert()
        alert.messageText = "Delete this Boost?"
        alert.informativeText = "Its changes to \(model.boost.host) go away."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BoostStore.shared.delete(model.boost.id)
        model.onClose()
    }
}

/// Arc's colour wheel: a rounded square in a grey gradient frame, dotted inside; the big handle is
/// the tint (hue round the middle, strength out from it), the small one sits at the middle.
private struct ColorWheel: View {
    let hue: Double
    let strength: Double
    let set: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width, inner = size - 14, c = size / 2
            let angle = hue * 2 * .pi, r = strength * (inner / 2 - 18)
            let handle = CGPoint(x: c + cos(angle) * r, y: c - sin(angle) * r)
            ZStack {
                // Arc's frame: brushed metal, dark at the top left and right, light at the bottom.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AngularGradient(colors: [Color(white: 0.55), Color(white: 0.25), Color(white: 0.45), Color(white: 0.85),
                                                   Color(white: 0.95), Color(white: 0.7), Color(white: 0.55)], center: .center, angle: .degrees(180)))
                    .overlay(strength > 0 ? RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(hue: hue, saturation: 0.5, brightness: 0.8).opacity(0.35)) : nil)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white).padding(7)
                Canvas { ctx, s in
                    for x in stride(from: 12.0, to: s.width - 12, by: 6) {
                        for y in stride(from: 12.0, to: s.height - 12, by: 6) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(0.12)))
                        }
                    }
                }
                // Arc's second, smaller handle: the darker end of the tint, between the middle and the big one.
                Circle().fill(Color(white: 0.17)).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 1.5)
                    .position(x: c + (handle.x - c) * 0.55 - 8, y: c + (handle.y - c) * 0.55 + 22)
                Circle().fill(strength > 0 ? Color(hue: hue, saturation: 0.6, brightness: 0.8) : Color(white: 0.45))
                    .frame(width: 32, height: 32).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 2)
                    .position(handle)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - c, dy = c - g.location.y
                var a = atan2(dy, dx) / (2 * .pi)
                if a < 0 { a += 1 }
                set(a, min(1, hypot(dx, dy) / (inner / 2 - 18)))
            })
        }
    }
}

/// The Code panel's editor: dark, monospaced, no smart quotes.
private struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        tv.textColor = NSColor(white: 0.92, alpha: 1)
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.delegate = context.coordinator
        tv.string = text
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        let tv = view.documentView as! NSTextView
        if tv.string != text { tv.string = text }
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { text.wrappedValue = tv.string } }
    }
}

/// The editor sits beside the page, which keeps the keyboard: its first click acts, as Arc's does.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Notification.Name {
    static let craShowBoostsLibrary = Notification.Name("craShowBoostsLibrary")
}
