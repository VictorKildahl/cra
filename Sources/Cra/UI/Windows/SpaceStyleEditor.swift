import AppKit
import SwiftUI

/// Arc 1.171's theme editor (SpaceStyleEditor), which Edit Theme Color… opens beside the
/// sidebar. Measured from 2x captures of an offline Arc (1 Nov): a 355 × 503 pt panel, the window
/// behind it darkened by ~58%; a 340 pt dotted colour pad with Auto / Light / Dark on top and − / +
/// (one to three colours) at the bottom; nine swatches between paging arrows (single colours, then
/// two-colour gradients); a wave slider for the intensity and a dotted dial for the grain. Every
/// change shows in the space at once.
struct SpaceStyleEditor: View {
    @State var theme: SpaceTheme
    let onChange: (SpaceTheme) -> Void

    static let swatchPages: [[[String]]] = [
        ["#F1EAE5", "#E69FBA", "#9E749B", "#E1686F", "#EF8C62", "#F2D66D", "#73E59C", "#7FB8D6", "#666786"].map { [$0] },
        [["#DCD2CF", "#C6BBBC"], ["#D397A2", "#BC89A8"], ["#976B86", "#7D617C"], ["#D07E6A", "#BA7087"], ["#DDA361", "#C88274"],
         ["#CACB6A", "#BB8F61"], ["#71CAAD", "#76B789"], ["#7B8FC2", "#7093A3"], ["#6F5F7F", "#646172"]],
    ]
    @State private var swatchPage = 0

    var body: some View {
        VStack(spacing: 0) {
            ColorPad(theme: $theme)
                .frame(width: 340, height: 340)
                .padding(.top, 9)
            HStack(spacing: 0) {
                pageArrow("chevron.left", to: swatchPage - 1)
                HStack(spacing: 5.5) {
                    ForEach(Self.swatchPages[swatchPage], id: \.self) { colors in
                        Circle()
                            .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                            .onTapGesture {
                                theme.colors = colors
                                theme.accent = colors.first
                            }
                    }
                }
                pageArrow("chevron.right", to: swatchPage + 1)
            }
            .padding(.top, 16.75)
            HStack(spacing: 0) {
                WaveSlider(value: $theme.intensity).frame(width: 224, height: 50)
                Spacer(minLength: 0)
                GrainDial(value: $theme.noise).frame(width: 70, height: 70)
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
        .onChange(of: theme) { _, t in onChange(t) }
    }

    private func pageArrow(_ symbol: String, to page: Int) -> some View {
        let ok = Self.swatchPages.indices.contains(page)
        return Button { if ok { swatchPage = page } } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 36, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(ok ? 0.55 : 0.2))
    }
}

/// The dotted pad, a colour wheel: a handle's angle (clockwise from three o'clock) is its hue and its
/// distance from the centre its saturation (full at 153 pt), brightness 0.95. A second and third
/// colour follow the first 40° either side; dragging any handle turns the set.
private struct ColorPad: View {
    @Binding var theme: SpaceTheme
    private static let reach: CGFloat = 153
    private static let spread: CGFloat = 40

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
                if theme.colors.isEmpty {
                    Text("Tap to pick a color for this space")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .allowsHitTesting(false)
                }
                ForEach(Array(theme.colors.prefix(3).enumerated()), id: \.offset) { i, hex in
                    let main = i == 0
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(.white, lineWidth: main ? 4.5 : 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: main ? 44 : 27, height: main ? 44 : 27)
                        .position(Self.point(for: hex, centre: centre))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in place(handle: i, at: g.location, centre: centre) })
                }
                VStack {
                    AppearanceToggles(appearance: $theme.appearance).padding(.top, 24)
                    Spacer()
                    HStack(spacing: 16) {
                        padButton("minus", enabled: theme.colors.count > 1) { theme.colors.removeLast() }
                        padButton("plus", enabled: !theme.colors.isEmpty && theme.colors.count < 3) { addColor() }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func padButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.18))
        .disabled(!enabled)
    }

    /// Handle `i` goes under the pointer; the others keep their place around it.
    private func place(handle i: Int, at p: CGPoint, centre c: CGPoint) {
        let dx = p.x - c.x, dy = p.y - c.y
        var angle = atan2(dy, dx) * 180 / .pi - Self.offset(i)
        angle = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let sat = min(1, hypot(dx, dy) / Self.reach)
        let count = max(1, theme.colors.count)
        theme.colors = (0..<count).map { Self.hex(hue: angle + Self.offset($0), saturation: sat) }
        theme.accent = theme.colors.first
    }

    private func addColor() {
        guard let first = theme.colors.first else { return }
        let (h, s) = Self.wheel(first)
        theme.colors.append(Self.hex(hue: h + Self.offset(theme.colors.count), saturation: s))
    }

    private static func offset(_ i: Int) -> CGFloat { i == 0 ? 0 : (i == 1 ? spread : -spread) }

    private static func hex(hue: CGFloat, saturation: CGFloat) -> String {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        return Color(nsColor: NSColor(hue: h, saturation: saturation, brightness: 0.95, alpha: 1)).hexString
    }

    private static func wheel(_ hex: String) -> (CGFloat, CGFloat) {
        let c = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .gray
        return (c.hueComponent * 360, c.saturationComponent)
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(appearance == value ? 0.8 : 0.55))
    }
}

/// The intensity: a wave over a 15 pt track with a white 16 × 46.5 pt thumb; the wave grows with the
/// value and is bright up to the thumb, faint after it.
private struct WaveSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x = 8 + (w - 16) * value
            let wave = Path { p in
                let amp = 3 + (h / 2 - 12) * value
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
