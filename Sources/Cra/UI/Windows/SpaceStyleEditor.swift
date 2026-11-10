import AppKit
import SwiftUI

/// Arc 1.171's theme editor (SpaceStyleEditor), which Edit Theme Color… opens beside the
/// sidebar and the Edit Space sheet shows inline. Measured from 2x captures of an offline Arc
/// (1 Nov): a 355 × 503 pt card, the window behind it darkened by ~58%; a 340 pt dotted colour pad
/// with Auto / Light / Dark on top and − / + (none to three colours; none is Arc's colourless
/// theme, SpaceThemeVariants.colourless) at the bottom; nine swatches
/// between paging arrows, five pages of Arc's catalog colours (SpaceColorPresets); a wave slider
/// for the intensity and a dotted dial for the grain. Every change goes to `onChange` at once (the
/// caller previews it); nothing here writes. Like Arc's editor state it keeps the pad's colours,
/// the intensity, the grain and Auto / Light / Dark, and builds the theme from them
/// (SpaceThemeVariants): one colour is Arc's one-dot fill, two or three a gradient, and Auto
/// always gets a light and a dark half (#155).
struct SpaceStyleEditor: View {
    @State private var theme: SpaceTheme
    @State private var pad: PadState
    let onChange: (SpaceTheme) -> Void

    init(theme: SpaceTheme, onChange: @escaping (SpaceTheme) -> Void) {
        _theme = State(initialValue: theme)
        // A one-colour theme stores its colour twice (a flat fill): one handle on the pad.
        let key = theme.key ?? (theme.solid || Set(theme.colors).count == 1 ? Array(theme.colors.prefix(1)) : theme.colors)
        _pad = State(initialValue: PadState(key: key, intensity: theme.intensity, noise: theme.noise, appearance: theme.appearance))
        // The page with the space's colour, else the one shown last (Arc: currentThemeEditorPresetPage).
        let last = UserDefaults.standard.integer(forKey: Self.pageKey)
        _swatchPage = State(initialValue: SpaceColorPresets.page(of: key)
            ?? (SpaceColorPresets.pages.indices.contains(last) ? last : 0))
        self.onChange = onChange
    }

    private static let pageKey = "themeEditorPresetPage"
    @State private var swatchPage: Int

    var body: some View {
        VStack(spacing: 0) {
            ColorPad(pad: $pad)
                .frame(width: 340, height: 340)
                .padding(.top, 9)
            HStack(spacing: 0) {
                pageArrow("chevron.left", to: swatchPage - 1, label: "Move to previous preset page.")
                HStack(spacing: 5.5) {
                    let page = SpaceColorPresets.pages[swatchPage]
                    ForEach(Array(page.swatches.enumerated()), id: \.offset) { i, colors in
                        Button { pad.key = colors } label: {
                            Circle()
                                .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(ColorPillButtonStyle())
                        // Arc: "Set space color to Catalog color: … ColorPickerBrandN".
                        .accessibilityLabel("Set space color to \(page.name(i))")
                    }
                }
                pageArrow("chevron.right", to: swatchPage + 1, label: "Move to next preset page.")
            }
            .padding(.top, 16.75)
            HStack(spacing: 0) {
                WaveSlider(value: $pad.intensity).frame(width: 224, height: 50)
                Spacer(minLength: 0)
                GrainDial(value: $pad.noise).frame(width: 70, height: 70)
            }
            .frame(height: 70)
            .padding(.leading, 17)
            .padding(.trailing, 23)
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .frame(width: 355, height: 503)
        // The space's own theme, darkened ~58% (Arc: #CDC2A5 behind → #554F37).
        .background(
            ZStack {
                SpaceBackground(palette: theme.palette)
                Color.black.opacity(0.58)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .environment(\.colorScheme, .dark)
        // Opening the editor leaves the theme as it is; the first change rebuilds it from the pad.
        .onChange(of: pad) { _, p in
            theme = SpaceThemeVariants.theme(key: p.key, intensity: p.intensity, noise: p.noise, appearance: p.appearance)
            onChange(theme)
        }
    }

    private func pageArrow(_ symbol: String, to page: Int, label: String) -> some View {
        let ok = SpaceColorPresets.pages.indices.contains(page)
        return PageArrow(symbol: symbol, enabled: ok, label: label) {
            swatchPage = page
            UserDefaults.standard.set(page, forKey: Self.pageKey)
        }
    }
}

/// A paging arrow: white 0.55, brighter under the pointer with a pointing hand (Arc's
/// SpaceStyleButtonStyle); the arrow past the last page is 0.2 and does neither. Not a SwiftUI
/// Button: a Button keeps the plain arrow pointer whatever pointer style it's given.
private struct PageArrow: View {
    let symbol: String
    let enabled: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hot = enabled && isHovered
        Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 36, height: 30)
            .contentShape(Rectangle())
            .foregroundStyle(.white.opacity(enabled ? (hot ? 0.85 : 0.55) : 0.2))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hot)
            .onHover { isHovered = $0 }
            .onTapGesture { if enabled { action() } }
            .editorPointer(enabled ? .link : nil)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction { if enabled { action() } }
    }
}

/// What the editor's controls set (Arc: SpaceStyleEditor.State's colours, factors and darkModeBiasSetting).
struct PadState: Equatable {
    var key: [String]
    var intensity: Double
    var noise: Double
    /// "auto", "light" or "dark".
    var appearance: String
}

/// The dotted pad, a colour wheel: a handle's angle (clockwise from three o'clock) is its hue and its
/// distance from the centre its saturation (full at 153 pt), brightness 0.95. A second and third
/// colour follow the first 40° either side; dragging any handle turns the set.
private struct ColorPad: View {
    @Binding var pad: PadState
    @State private var hoveredKnob: Int?
    @State private var draggingKnob: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let reach: CGFloat = 153

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.04))
                Canvas { ctx, s in
                    var p = Path()
                    for x in stride(from: 4.0, to: s.width, by: 4) {
                        for y in stride(from: 4.0, to: s.height, by: 4) { p.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)) }
                    }
                    ctx.fill(p, with: .color(.white.opacity(0.12)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                // Arc: pressing anywhere on the pad brings the main colour there, and it follows the drag.
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in place(handle: 0, at: g.location, centre: centre) })
                if pad.key.isEmpty {
                    Text("Tap to pick a color for this space")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .allowsHitTesting(false)
                }
                ForEach(Array(pad.key.prefix(3).enumerated()), id: \.offset) { i, hex in
                    let main = i == 0
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(.white, lineWidth: main ? 4.5 : 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: main ? 44 : 27, height: main ? 44 : 27)
                        // Arc's PadWheel knob: grows under the pointer, shrinks while held (the
                        // swatches' scales); an open hand over it, a closed one while dragging.
                        .scaleEffect(draggingKnob == i ? ColorPillButtonStyle.pressed : hoveredKnob == i ? ColorPillButtonStyle.hovered : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredKnob == i)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: draggingKnob == i)
                        .onHover { inside in
                            if inside { hoveredKnob = i } else if hoveredKnob == i { hoveredKnob = nil }
                        }
                        // Arc: an open hand over a knob, a closed one while dragging it.
                        .editorPointer(draggingKnob == i ? .grabbing : .grab)
                        .position(Self.point(for: hex, centre: centre))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                // SwiftUI re-reads pointer styles on moves, not drags: hold the closed hand.
                                if #available(macOS 15, *) { NSCursor.closedHand.set() }
                                draggingKnob = i
                                place(handle: i, at: g.location, centre: centre)
                            }
                            .onEnded { _ in draggingKnob = nil })
                }
                VStack {
                    AppearanceToggles(appearance: $pad.appearance).padding(.top, 24)
                    Spacer()
                    HStack(spacing: 16) {
                        // − takes the last colour too: an empty pad is Arc's colourless theme (#300).
                        padButton("minus", label: "Remove a color", enabled: SpaceColorWheel.canRemove(pad.key.count)) { pad.key.removeLast() }
                        padButton("plus", label: "Add a color", enabled: SpaceColorWheel.canAdd(pad.key.count)) { addColor() }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func padButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(SpaceStyleButtonStyle(opacity: enabled ? 0.55 : 0.18, enabled: enabled))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Handle `i` goes under the pointer; the others keep their place around it.
    private func place(handle i: Int, at p: CGPoint, centre c: CGPoint) {
        let dx = p.x - c.x, dy = p.y - c.y
        var angle = atan2(dy, dx) * 180 / .pi - Self.offset(i)
        angle = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let sat = min(1, hypot(dx, dy) / Self.reach)
        let count = max(1, pad.key.count)
        pad.key = (0..<count).map { Self.hex(hue: angle + Self.offset($0), saturation: sat) }
    }

    private func addColor() {
        guard let first = pad.key.first else { return }
        let (h, s) = Self.wheel(first)
        pad.key.append(Self.hex(hue: h + Self.offset(pad.key.count), saturation: s))
    }

    private static func offset(_ i: Int) -> CGFloat { CGFloat(SpaceColorWheel.offset(i)) }

    private static func hex(hue: CGFloat, saturation: CGFloat) -> String {
        SpaceColorWheel.hex(hue: Double(hue), saturation: Double(saturation), brightness: 0.95)
    }

    private static func wheel(_ hex: String) -> (CGFloat, CGFloat) {
        let w = SpaceColorWheel.hsb(hex)
        return (CGFloat(w.hue), CGFloat(w.saturation))
    }

    static func point(for hex: String, centre c: CGPoint) -> CGPoint {
        let (h, s) = wheel(hex)
        let a = h * .pi / 180, r = s * reach
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
}

/// Auto (sparkles), Light (sun) and Dark (moon) over the pad; the chosen one on a 32 pt tile.
private struct AppearanceToggles: View {
    @Binding var appearance: String

    var body: some View {
        HStack(spacing: 7.5) {
            toggle("auto", symbol: "sparkles")
            toggle("light", symbol: "sun.max.fill")
            toggle("dark", symbol: "moon.stars.fill")
        }
    }

    private func toggle(_ value: String, symbol: String) -> some View {
        Button { appearance = value } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(appearance == value ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(SpaceStyleButtonStyle(opacity: appearance == value ? 0.8 : 0.55, enabled: appearance != value))
    }
}

/// The intensity: a wave over a 15 pt track with a white 16 × 46.5 pt thumb; the wave grows with the
/// value and is bright up to the thumb, faint after it.
private struct WaveSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x = 8 + (w - 16) * CGFloat(value)
            let wave = Path { p in
                let amp = 3 + (h / 2 - 12) * CGFloat(value)
                for px in stride(from: 8.0, through: w - 8, by: 1) {
                    let y = h / 2 - amp * sin((px - 8) / (w - 16) * CGFloat.pi * 14)
                    px == 8 ? p.move(to: CGPoint(x: px, y: y)) : p.addLine(to: CGPoint(x: px, y: y))
                }
            }
            let style = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1)).frame(height: 15)
                wave.stroke(.white.opacity(0.25), style: style)
                wave.stroke(.white.opacity(0.75), style: style).mask(Rectangle().frame(width: x).frame(maxWidth: .infinity, alignment: .leading))
                Capsule().fill(.white).frame(width: 16, height: 46.5).position(x: x, y: h / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in value = min(max((g.location.x - 8) / (w - 16), 0), 1) })
        }
    }
}

/// The grain: a dark disc showing it, a ring of dots lit from twelve o'clock round to a white knob;
/// turning the knob sets the value.
private struct GrainDial: View {
    @Binding var value: Double
    private let count = 24

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let knob = value * 2 * .pi - .pi / 2
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
                    Circle()
                        .fill(.white.opacity(Double(i) / Double(count) <= value ? 0.55 : 0.18))
                        .frame(width: 3.5, height: 3.5)
                        .position(x: c.x + 34 * cos(a), y: c.y + 34 * sin(a))
                }
                Circle().fill(.black.opacity(0.12)).overlay(NoiseDisc(amount: value)).clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .frame(width: 41, height: 41)
                Capsule().fill(.white).frame(width: 4.5, height: 12)
                    .rotationEffect(.radians(knob + .pi / 2))
                    .position(x: c.x + 31 * cos(knob), y: c.y + 31 * sin(knob))
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                var a = atan2(g.location.y - c.y, g.location.x - c.x) + .pi / 2
                if a < 0 { a += 2 * .pi }
                value = a / (2 * .pi)
            })
        }
    }
}

/// The dial's face: the theme's grain texture at the chosen strength.
private struct NoiseDisc: View {
    let amount: Double
    var body: some View {
        Rectangle().fill(ImagePaint(image: Image(nsImage: NoiseTexture.image), scale: 0.5)).opacity(0.15 + 0.6 * amount)
    }
}

/// Arc's ColorPillButtonStyle for the preset swatches: a circle grows a little under the pointer and
/// shrinks while pressed, both eased; scaled, never resized, so the row keeps its 29.5 pt pitch.
/// The pad's knobs use the same scales (GitHub #189).
struct ColorPillButtonStyle: ButtonStyle {
    static let hovered: CGFloat = 1.08
    static let pressed: CGFloat = 0.92
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressed : isHovered ? Self.hovered : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Arc's SpaceStyleButtonStyle (paging arrows, − / +, Auto / Light / Dark): white at `opacity`,
/// brighter under the pointer while it can be pressed.
struct SpaceStyleButtonStyle: ButtonStyle {
    var opacity: Double
    var enabled = true
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let hot = enabled && isHovered
        return configuration.label
            .foregroundStyle(.white.opacity(hot ? min(1, opacity + 0.3) : opacity))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hot)
            .onHover { isHovered = $0 }
    }
}

/// The pointer Arc shows over the editor: a pointing hand on a paging arrow, an open hand over a
/// pad knob and a closed one while dragging it. SwiftUI's pointer styles (macOS 15 and later; on 14
/// the arrow stays).
enum EditorPointer { case link, grab, grabbing }

extension View {
    @ViewBuilder func editorPointer(_ pointer: EditorPointer?) -> some View {
        if #available(macOS 15, *), let pointer {
            switch pointer {
            case .link: self.pointerStyle(.link)
            case .grab: self.pointerStyle(.grabIdle)
            case .grabbing: self.pointerStyle(.grabActive)
            }
        } else {
            self
        }
    }
}
