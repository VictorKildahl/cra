import AppKit
import Observation
import SwiftUI

/// Colors derived from a space theme, the way Arc derives a
/// semanticColorPalette from the window theme.
struct SpacePalette {
    let isDark: Bool
    let gradientColors: [Color]
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let hoverFill: Color
    let selectedFill: Color
    let separator: Color
    /// The sidebar URL pill and a favorite tile at rest; both take `pillHoverFill` under the pointer.
    let pillFill: Color
    /// Arc 1.172.1 (live, 9 Nov 2026, GitHub #293): the URL pill and the favorite tiles share one hover,
    /// a shade darker on light themes and lighter on dark ones. Cra's pill went near-white instead.
    let pillHoverFill: Color
    let toolbarFill: Color
    let folderTint: Color
    /// Light themes: Arc's folder glyph (FolderTones), an opaque front in tintedLight, the outline in
    /// shadedDark and the back panel in midTone. Dark themes keep Cra's own: white at 14 % (fill) and
    /// 85 % (outline) over the sidebar, flattened onto the sidebar's colour so an open folder is opaque.
    let folderFill: Color
    let folderBack: Color
    /// A renamed split's pane count (Arc: the palette's cutoutColor). Arc 1.171 live, 3 Nov: the theme
    /// colour at ~60% on a dark theme; a light theme takes tintedLight, as the folder front does.
    let countBadgeFill: Color
    let noise: Double
    /// Opacity of the gradient over the blurred desktop at the top and bottom
    /// stops (1 when not vibrant). Arc's light themes get more opaque downwards.
    let gradientAlpha: Double
    let gradientAlphaBottom: Double
    let vibrant: Bool
    /// One flat colour over Arc's solid-theme material (ShellView.solidBackdrop).
    let solid: Bool
    /// Whether that material is Arc's light one: the space's Light or Dark, or macOS' on Auto (#455).
    var lightMaterial = false
    /// A gradient whose colours read dark, over Arc's darker material for those (#643).
    var darkGradient = false
    /// Settings ▸ Tabs ▸ "Translucent sidebar" (Ideas #366): the colours over SidebarGlass's material.
    var glass = false
    /// One colour over Arc's material, and whether macOS itself shows Dark: with the window inactive, Arc lays both
    /// on a dark grey on macOS Dark (SidebarBackdrop.solidInactiveDark, #876).
    var oneColour = false
    var macOSDark = false
    /// The sidebar's colour at the bottom of the tab list, opaque, as it shows over its material: what a
    /// now-playing card in the theme's colour is laid over (NowPlayingTint.theme, Ideas #366).
    var playerGround: Color = .clear

    /// Arc's one-colour opacity (SpaceTheme.solidAlpha, where the measurements are).
    static func solidAlpha(intensity: Double) -> Double { SpaceTheme.solidAlpha(intensity: intensity) }

    /// Outline and fill for a folder glyph; nil (Auto) is the theme's pair.
    func folderColors(_ style: FolderIconStyle?) -> (tint: Color, fill: Color, back: Color) {
        switch style {
        case nil: return (folderTint, folderFill, folderBack)
        case .white?: return (.white.opacity(0.92), .white.opacity(0.22), .white.opacity(0.22))
        case .black?: return (.black.opacity(0.8), .black.opacity(0.12), .black.opacity(0.12))
        }
    }
}

extension SpaceTheme {
    static func blend(_ a: String, _ b: String, _ t: Double) -> Color {
        let x = HexColor.components(a) ?? (0.5, 0.5, 0.5), y = HexColor.components(b) ?? (0.5, 0.5, 0.5)
        let k = max(0, min(1, t))
        return Color(.sRGB, red: x.r + (y.r - x.r) * k, green: x.g + (y.g - x.g) * k, blue: x.b + (y.b - x.b) * k, opacity: 1)
    }

    private static func mix(_ hex: String, towardWhite: Bool, amount: Double) -> Color {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let target = towardWhite ? 1.0 : 0.0
        let a = max(0, min(1, amount))
        return Color(.sRGB, red: c.r + (target - c.r) * a, green: c.g + (target - c.g) * a, blue: c.b + (target - c.b) * a, opacity: 1)
    }

    /// Arc's toolbar band: the first theme colour pushed to a dark, fully
    /// saturated shade on light themes (Victor: #72601D) and a muted,
    /// slightly darker one on dark themes (JYSK: #0E0B16).
    /// Light: 46% brightness, saturation +0.10 (Victor #F8D558 → #725F1D, Arc #72601D).
    /// Dark: 60% saturation, 80% brightness (JYSK #010220 → #0A0B19, Arc #0E0B16).
    /// Arc's light-theme ink: the first theme colour pushed to ~13% brightness
    /// (Victor #F8D558 → ≈#201A0C; Arc's row titles sample 32/26/0).
    static func inkColor(_ hex: String) -> Color {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        var (h, s, v) = hsb(c.r, c.g, c.b)
        s = min(1, s + 0.10); v *= 0.135
        let o = rgb(h: h, s: s, v: v)
        return Color(.sRGB, red: o.0, green: o.1, blue: o.2, opacity: 1)
    }

    static func toolbarColor(_ hex: String, dark: Bool) -> Color {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        var (h, s, v) = hsb(c.r, c.g, c.b)
        if dark { s *= 0.6; v *= 0.8 } else { s = min(1, s + 0.10); v *= 0.46 }
        let o = rgb(h: h, s: s, v: v)
        return Color(.sRGB, red: o.0, green: o.1, blue: o.2, opacity: 1)
    }

    /// The theme as macOS shows it now: an Auto theme's light or dark half. Read under
    /// observation tracking, a switch of macOS' appearance redraws whatever showed the old half.
    var shown: SpaceTheme { resolved(systemDark: SystemAppearance.shared.isDark) }

    var palette: SpacePalette {
        let systemDark = SystemAppearance.shared.isDark
        let forcedDark = SystemAppearance.shared.forcedDark
        let glass = SidebarGlassSetting.shared.isOn
        let theme = resolved(systemDark: systemDark)
        let lightMaterial = usesLightMaterial(systemDark: systemDark, forcedDark: forcedDark)
        var p = theme.fixedPalette(lightMaterial: lightMaterial, glass: glass)
        // The glass's own material follows the theme's colours (SidebarGlass), not Arc's light/dark pick.
        p.lightMaterial = glass ? !theme.isDark : lightMaterial
        p.darkGradient = !glass && theme.drawnOverDarkGradientMaterial
        p.glass = glass
        p.oneColour = !glass && theme.solid
        p.macOSDark = SystemAppearance.shared.macOSDark
        return p
    }

    /// The palette of a resolved theme (its appearance is light or dark, or judged by colour).
    /// `glass`: Settings ▸ Tabs ▸ "Translucent sidebar" (Ideas #366), every theme thin over SidebarGlass.
    private func fixedPalette(lightMaterial: Bool, glass: Bool = false) -> SpacePalette {
        let dark = isDark
        let base = colors.isEmpty ? ["#DDDDDD"] : colors
        // Over Arc's material (one colour, or a gradient made in the editor, #643): the colours at
        // Arc's one-colour opacity. Vibrant (an imported Arc theme): its stops at `intensity` over the blur.
        // Opaque: intensity 1 = the raw colors; lower pulls toward white/black.
        let overMaterial = drawnOverMaterial || glass
        let pull = vibrant || solid || glass ? 0 : (1 - intensity) * (dark ? 0.35 : 0.6)
        var stops = base.map { SpaceTheme.mix($0, towardWhite: !dark, amount: pull) }
        if stops.count == 1 { stops.append(SpaceTheme.mix(base[0], towardWhite: !dark, amount: pull + 0.15)) }

        let folder = FolderTones(themeColor: self.accent ?? base[0], dark: dark)
        let alphaTop = glass ? SidebarGlass.alpha(intensity: intensity) : overMaterial ? SpacePalette.solidAlpha(intensity: intensity)
            : vibrant ? (dark ? max(0.35, min(0.9, intensity * 2.2)) : min(0.95, intensity * 1.70)) : 1
        let alphaBottom = glass ? SidebarGlass.alpha(intensity: intensity) : overMaterial ? SpacePalette.solidAlpha(intensity: intensity)
            : vibrant ? (dark ? max(0.35, min(0.9, intensity * 2.2)) : min(0.95, intensity * 2.35)) : 1
        // Dark themes: Arc's palette tones (shadedDark front, midTone back) read wrong next to Cra's
        // dark sidebar (Victor, 4 Nov), so the folder keeps the earlier white-over-sidebar look, made
        // opaque. Under a translucent theme the sidebar is the top colour over the dark material
        // (underWindowBackground with ShellView's lift), about 20 % white; a solid one on Light is over
        // Arc's light material instead, about 75 % white over a typical desktop (#455).
        let material = glass ? SidebarGlass.ground(dark: dark) : overMaterial && lightMaterial ? 0.75 : 0.2
        let ground = alphaTop < 1 ? Color(white: material).blendedToward(stops[0], alphaTop) : stops[0]
        let darkFill = ground.blendedToward(.white, 0.14)
        let bottom = stops[stops.count - 1]
        let playerGround = alphaBottom < 1 ? Color(white: material).blendedToward(bottom, alphaBottom) : bottom
        var palette = SpacePalette(
            isDark: dark,
            gradientColors: stops,
            textPrimary: dark ? .white.opacity(0.92) : SpaceTheme.inkColor(self.accent ?? base[0]),
            textSecondary: dark ? .white.opacity(0.6) : .black.opacity(0.5),
            textTertiary: dark ? .white.opacity(0.38) : .black.opacity(0.38),
            // Arc 1.170 live: a hovered row darkens ~4.5% (220/210/171 → 210/200/163), it does not lighten.
            hoverFill: dark ? .white.opacity(0.07) : .black.opacity(0.045),
            selectedFill: dark ? .white.opacity(0.13) : .white.opacity(0.74),
            separator: dark ? .white.opacity(0.12) : .black.opacity(0.09),
            pillFill: Color(SidebarTones.pill(dark: dark)),
            pillHoverFill: Color(SidebarTones.pillHover(dark: dark)),
            // Arc: the toolbar is the first theme color at ~46% (dark) / lightened a touch (dark themes).
            toolbarFill: SpaceTheme.toolbarColor(self.accent ?? base[0], dark: dark),
            folderTint: dark ? ground.blendedToward(.white, 0.85) : Color(folder.outline),
            folderFill: dark ? darkFill : Color(folder.front),
            folderBack: dark ? darkFill : Color(folder.back),
            countBadgeFill: dark ? Color(hex: self.accent ?? base[0]).opacity(0.6) : Color(folder.front),
            noise: noise,
            // Calibrated against Arc's rendering of a 0.25-intensity vibrant theme.
            // Fitted to Arc's Victor theme (intensity 0.25) over white and black
            // backdrops: light vibrant themes run 0.45 → 0.59 over a HUD blur
            // (which passes ~55% of the backdrop and adds ~30/255 grey).
            // Re-fitted 25 Oct against Arc 1.170 over solid white/black backdrops (same
            // screen, same window frame): Arc's sidebar = c + k·backdrop with k 0.32 → 0.23
            // and c 123/116/83 → 159/129/95 (Victor theme). The dark HUD material (own tint
            // 27, passes 52 %) could not reach both, so light vibrant themes now blur through
            // an untinted CABackdropLayer with a 0.19 dim and a 0.16→0.18 lift (ShellView);
            // opacity 0.43 top / 0.59 bottom then matches Arc within ±5 over white and black.
            gradientAlpha: alphaTop,
            gradientAlphaBottom: alphaBottom,
            vibrant: vibrant || solid || glass,
            solid: overMaterial
        )
        palette.playerGround = playerGround
        return palette
    }
}

/// Settings ▸ Tabs ▸ "Translucent sidebar" (Ideas #366), which every palette reads: the windows'
/// refresh copies it from the store, and views drawn from a palette redraw when it changes.
@Observable
final class SidebarGlassSetting: @unchecked Sendable {
    static let shared = SidebarGlassSetting()
    /// Written on the main thread only.
    var isOn = false
}

/// The app's light or dark appearance, which an Auto space theme follows (Arc: appearanceBased):
/// macOS', unless View ▸ Appearance sets NSApp.appearance to Light or Dark, as Arc's does (#362).
@Observable
final class SystemAppearance: @unchecked Sendable {
    static let shared = SystemAppearance()
    /// Written on the main thread only.
    private(set) var isDark = false
    /// View ▸ Appearance set to Dark (true) or Light (false), nil on Automatic: every space's sidebar
    /// takes it, as Arc's one appearance setting does (#700).
    private(set) var forcedDark: Bool?

    /// macOS's own Light or Dark, also while View ▸ Appearance forces the app's: what Arc's material follows when
    /// its window is inactive (#876). macOS writes AppleInterfaceStyle "Dark" in Dark and none in Light.
    var macOSDark: Bool {
        forcedDark == nil ? isDark : UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// View ▸ Appearance changed (WebsiteAppearance.forcesDark).
    @MainActor func setForced(_ dark: Bool?) { if dark != forcedDark { forcedDark = dark } }
    @ObservationIgnored private var observation: NSKeyValueObservation?

    @MainActor func start() {
        update()
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    @MainActor private func update() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark != isDark { isDark = dark }
    }
}

extension Color {
    /// A sidebar tone: white or black at its opacity.
    init(_ tone: SidebarTones.Tone) { self = (tone.white ? Color.white : Color.black).opacity(tone.alpha) }

    /// Mix toward another color in sRGB (amount 0...1).
    func blendedToward(_ other: Color, _ amount: Double) -> Color {
        guard amount > 0 else { return self }
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let t = max(0, min(1, amount))
        return Color(.sRGB, red: Double(a.redComponent + (b.redComponent - a.redComponent) * t),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * t),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * t), opacity: 1)
    }
}

struct NoiseOverlay: View {
    let amount: Double
    let isDark: Bool
    var body: some View {
        Image(nsImage: NoiseTexture.image)
            .resizable(resizingMode: .tile)
            .opacity(amount * (isDark ? 0.1 : 0.09))
            .blendMode(isDark ? .screen : .multiply)
            .allowsHitTesting(false)
    }
}

struct SpaceBackground: View {
    let palette: SpacePalette

    var body: some View {
        gradient
    }

    private var gradient: some View {
        let colors = Self.samples(palette)
        let stops = colors.enumerated().map { i, c in
            Gradient.Stop(color: Color(nsColor: c), location: Double(i) / Double(max(1, colors.count - 1)))
        }
        return ZStack {
            // Arc's axis (#669): 45° from the top left, the last colour 0.76 of the way to the far corner.
            GeometryReader { g in
                let e = SpaceGradient.unitEnd(width: g.size.width, height: g.size.height)
                LinearGradient(stops: stops, startPoint: .topLeading, endPoint: UnitPoint(x: e.x, y: e.y))
            }
            NoiseOverlay(amount: palette.noise, isDark: palette.isDark)
        }
        .ignoresSafeArea()
    }

    /// Colours sampled evenly along the gradient, blended in Oklab as Arc's are (#669); a gradient
    /// layer's straight blend between this many is within 1/255 of the curve.
    static let sampleCount = 9

    static func samples(_ palette: SpacePalette) -> [NSColor] {
        let stops = stops(palette).map { s -> SpaceGradient.RGBA in
            let c = s.color.usingColorSpace(.sRGB) ?? .gray
            return SpaceGradient.RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
        }
        return SpaceGradient.samples(stops, count: sampleCount).map {
            NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: $0.a)
        }
    }

    /// A gradient layer's start and end for a frame of `size` (unit points, y up as Core Animation has them).
    static func layerAxis(_ size: CGSize) -> (start: CGPoint, end: CGPoint) {
        guard size.width > 0, size.height > 0 else { return (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)) }
        let e = SpaceGradient.unitEnd(width: size.width, height: size.height)
        return (CGPoint(x: 0, y: 1), CGPoint(x: e.x, y: 1 - e.y))
    }

    /// The theme's colours as drawn: each carries the palette's alpha from the first stop to the last.
    static func stops(_ palette: SpacePalette) -> [(color: NSColor, location: Double)] {
        let scale = palette.vibrant ? CraTuning.shared.gradientAlphaScale : 1
        let n = palette.gradientColors.count
        return palette.gradientColors.enumerated().map { i, c in
            let t = n > 1 ? Double(i) / Double(n - 1) : 0
            let top = palette.gradientAlpha * (palette.vibrant ? CraTuning.shared.gradientAlphaTopScale : 1)
            let bottom = palette.gradientAlphaBottom * (palette.vibrant ? CraTuning.shared.gradientAlphaBottomScale : 1)
            let a = min(1, (top + (bottom - top) * t) * scale)
            let rgb = NSColor(c).usingColorSpace(.sRGB) ?? .gray
            return (rgb.withAlphaComponent(rgb.alphaComponent * a), t)
        }
    }
}

/// The main window's background in AppKit: the paged space gradient (Core Animation) under the
/// theme's noise. It follows the window's focused space itself; a space switch used to rebuild a
/// SwiftUI background whenever the theme changed.
@MainActor
final class SpaceBackgroundView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let gradient: PagedGradientView
    private let noise = ThemeNoiseView()

    init(store: SidebarStore, ui: SidebarUIState) {
        self.store = store
        self.ui = ui
        gradient = PagedGradientView(store: store, ui: ui)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(gradient)
        addSubview(noise)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func observe() {
        let palette = withObservationTracking { store.focusedSpace(window: ui.windowID).theme.palette } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        noise.apply(palette)
    }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        noise.frame = bounds
    }

}

extension ThemeNoiseView {
    func apply(_ palette: SpacePalette) { apply(noise: palette.noise, isDark: palette.isDark) }
}

/// SpaceBackground(palette:) in AppKit, for a view that shows one palette (the floating sidebar).
final class PaletteBackgroundView: NSView {
    var palette: SpacePalette { didSet { apply() } }
    private let gradient = CAGradientLayer()
    private let noise = ThemeNoiseView()

    init(palette: SpacePalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(gradient)
        addSubview(noise)
        apply()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func apply() {
        let colors = SpaceBackground.samples(palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
        CATransaction.commit()
        noise.apply(palette)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let axis = SpaceBackground.layerAxis(bounds.size)
        gradient.startPoint = axis.start
        gradient.endPoint = axis.end
        CATransaction.commit()
        noise.frame = bounds
    }
}

/// The window tint while paging between spaces: the two neighbouring spaces' gradients mixed
/// colour by colour at the fractional page position (Dia blends its space tint with the paging
/// progress). A gradient layer set straight from the swipe, and sprung by Core Animation when it
/// settles: in SwiftUI it re-rendered and re-laid out the window's background on every frame.
@MainActor
final class PagedGradientView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let gradient = CAGradientLayer()
    private var placed: (index: Int, ids: [UUID], swipe: CGFloat)?
    private var pendingVelocity = 0.0
    private static let samples = SpaceBackground.sampleCount
    private static let settleKey = "settle"

    init(store: SidebarStore, ui: SidebarUIState) {
        self.store = store
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        gradient.locations = (0..<Self.samples).map { NSNumber(value: Double($0) / Double(Self.samples - 1)) }
        layer?.addSublayer(gradient)
        ui.observeSpaceSwipe { [weak self] in self?.swipeChanged() }
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func observe() {
        withObservationTracking {
            _ = store.pagedSpaces(window: ui.windowID).map(\.theme)
            _ = store.focusedSpaceID(window: ui.windowID)
            _ = CraTuning.shared.gradientAlphaScale
            _ = SidebarGlassSetting.shared.isOn
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.placed = nil
                self?.observe()
            }
        }
        needsLayout = true
    }

    private func swipeChanged() {
        if ui.spaceSwipe == 0 { pendingVelocity = ui.spaceSettleVelocity }
        // Under the fingers the tint follows at once; a settle waits for the space change.
        if ui.spaceSwipe != 0 { update() } else { needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        // Arc's axis across the whole window (#669).
        let axis = SpaceBackground.layerAxis(bounds.size)
        gradient.startPoint = axis.start
        gradient.endPoint = axis.end
        CATransaction.commit()
        update()
    }

    private func update() {
        let spaces = store.pagedSpaces(window: ui.windowID)
        guard !spaces.isEmpty else { return }
        let ids = spaces.map(\.id)
        let index = ids.firstIndex(of: store.focusedSpaceID(window: ui.windowID)) ?? 0
        let palettes = spaces.map(\.theme.palette)
        let swipe = ui.spaceSwipe
        let target = Self.colors(palettes, at: Double(index) + Double(swipe))
        let moved = placed.map { $0.index != index || $0.swipe != 0 } ?? false
        let sameSpaces = placed?.ids == ids
        placed = (index, ids, swipe)
        if swipe == 0, moved, sameSpaces, let from = gradient.presentation()?.colors ?? gradient.colors {
            // The strip's spring, Arc's (LibrarySwipe.response, #613): on Dia's 0.4 s the tint trailed the sidebar.
            let spring = CASpringAnimation(perceptualDuration: LibrarySwipe.response, bounce: 0)
            spring.keyPath = "colors"
            spring.fromValue = from
            spring.toValue = target
            spring.initialVelocity = pendingVelocity
            spring.duration = spring.settlingDuration
            pendingVelocity = 0
            setColors(target)
            gradient.add(spring, forKey: Self.settleKey)
        } else {
            if swipe != 0 { gradient.removeAnimation(forKey: Self.settleKey) }
            setColors(target)
        }
    }

    /// `cra://debug?spaceGradient=<label>`: the layer's axis and colours, which run at Arc's 45° from
    /// the top left, the last colour 0.76 of the way to the far corner (#669).
    var debugReadout: String {
        let w = bounds.width, h = bounds.height
        let s = gradient.startPoint, e = gradient.endPoint
        // Where the layer puts the far corner and the top right / bottom left, as `SpaceGradient.position` does.
        func at(_ x: Double, _ y: Double) -> Double {
            let ex = e.x - s.x, ey = (1 - e.y) - (1 - s.y), n = ex * ex + ey * ey
            return n > 0 ? max(0, min(1, (x / w * ex + y / h * ey) / n)) : 0
        }
        return String(format: "size %dx%d start %.3f,%.3f end %.3f,%.3f topRight %.3f bottomLeft %.3f colours %d",
                      Int(w), Int(h), s.x, s.y, e.x, e.y, at(w, 0), at(0, h), gradient.colors?.count ?? 0)
    }

    private func setColors(_ colors: [CGColor]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors
        CATransaction.commit()
    }

    static func colors(_ palettes: [SpacePalette], at position: Double) -> [CGColor] {
        let last = max(0, palettes.count - 1)
        let p = min(max(position, 0), Double(last))
        let lo = Int(p.rounded(.down)), hi = min(last, lo + 1)
        let f = p - Double(lo)
        let a = SpaceBackground.samples(palettes[lo]), b = SpaceBackground.samples(palettes[hi])
        return zip(a, b).map { mix($0, $1, f).cgColor }
    }

    private static func mix(_ x: NSColor, _ y: NSColor, _ f: Double) -> NSColor {
        let x = x.usingColorSpace(.sRGB) ?? x, y = y.usingColorSpace(.sRGB) ?? y
        let g = CGFloat(f)
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * g,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * g,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * g,
                       alpha: x.alphaComponent + (y.alphaComponent - x.alphaComponent) * g)
    }
}

/// Layout constants measured from Arc 1.168 at 2x (see docs).
enum CraMetrics {
    static let sidebarDefaultWidth: CGFloat = 328
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 1
    static let rowCorner: CGFloat = 10
    static let favicon: CGFloat = 16
    /// A nested row's step in (Arc 1.171, measured at 1x: favicon 26 → 42, text 45 → 61; GitHub #139).
    static let indent: CGFloat = 16
    /// Arc 1.171 at 1x (GitHub #139): a row's fill starts 8 pt in from the sidebar's edge and its
    /// favicon 10 pt into the fill (18 pt in), the same on the right (fill ends 8 pt short).
    static let rowInset: CGFloat = 8
    static let rowLeading: CGFloat = 10
    static let contentInset: CGFloat = 10
    static let contentCornerRadius: CGFloat = 6
    static let toolbarHeight: CGFloat = 32
    /// Arc's developer-mode bar is taller (Arc 1.170 at 2x: 80 px against 64).
    static let developerToolbarHeight: CGFloat = 40
    /// Traffic lights, sidebar toggle and nav buttons share this centre line.
    static let titleRowCenter: CGFloat = 24
    static let titleAreaHeight: CGFloat = 44
    static let commandBarWidth: CGFloat = 766
    static let findBarSize = NSSize(width: 300, height: 38)
    /// Gap between the find bar and the page's top and trailing edges.
    static let findBarInset: CGFloat = 10
}
