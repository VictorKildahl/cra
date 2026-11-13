import SwiftUI

/// Geometry of Arc 1.172.2's Settings window, measured on 11 and 12 Nov 2026 from its window captures and
/// accessibility tree (GitHub #372): 684 × 650 pt, a toolbar of tabs from y 32 to 88, a body of 562 pt under it,
/// cards 556 pt wide with a 64 pt margin.
enum SettingsMetrics {
    static let windowSize = CGSize(width: 684, height: 650)
    /// The tabs sit 32 pt down (under the title bar); the selected one's pill is 47 pt tall and the bar ends,
    /// with its hairline, at y 88.
    static let tabBarTop: CGFloat = 32
    static let tabBarHeight: CGFloat = 56
    static let tabPillHeight: CGFloat = 47
    static let tabMinWidth: CGFloat = 55
    static let tabCorner: CGFloat = 7
    /// Cards sit 64 pt from the window's sides, 20 pt below the bar.
    static let paneInset: CGFloat = 64
    static let paneTop: CGFloat = 20
    static let paneBottom: CGFloat = 20
    static let cardCorner: CGFloat = 5.5
    static let cardRowInset: CGFloat = 10
    static let cardRowHeight: CGFloat = 36
    static let controlHeight: CGFloat = 24
    static let switchSize = CGSize(width: 36, height: 16)
}

/// Arc's Settings colours as they read in its window captures (raw Display P3 bytes, dark and light). The
/// window follows the system appearance. Victor (12 Nov 2026): not Arc's navy; the window keeps the
/// system's window colour Cra's Settings had before, with the cards and hairlines laid over it as before.
enum SettingsPalette {
    private static func p3(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(displayP3Red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    private static func white(_ a: CGFloat) -> NSColor { NSColor.white.withAlphaComponent(a) }
    private static func black(_ a: CGFloat) -> NSColor { NSColor.black.withAlphaComponent(a) }

    static let window = NSColor.windowBackgroundColor
    /// The hairline under the tabs.
    static let tabLine = dynamic(dark: white(0.08), light: black(0.08))
    static let card = dynamic(dark: white(0.05), light: white(0.6))
    /// Card border and the hairlines between rows.
    static let hairline = dynamic(dark: white(0.1), light: black(0.1))
    static let selectedTab = dynamic(dark: white(0.1), light: p3(255, 255, 255))
    static let selectedTabBorder = dynamic(dark: white(0.12), light: p3(255, 255, 255))
    /// A chosen row of a list (the profiles).
    static let selectedRow = dynamic(dark: white(0.1), light: black(0.06))
    static let switchOff = dynamic(dark: white(0.22), light: p3(224, 224, 224))
    static let knobOn = dynamic(dark: p3(223, 235, 255), light: p3(255, 255, 255))
    static let knobOff = dynamic(dark: p3(200, 200, 205), light: p3(255, 255, 255))
}

extension Color {
    /// Arc's blue (a chosen tab, a switch that is on): the system's own.
    static let settingsBlue = Color(nsColor: .systemBlue)
    static let settingsWindow = Color(nsColor: SettingsPalette.window)
    static let settingsHairline = Color(nsColor: SettingsPalette.hairline)
}

/// Arc's switch: 36 × 16 pt, a round knob 3 pt inside the track.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let size = SettingsMetrics.switchSize
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Color.settingsBlue : Color(nsColor: SettingsPalette.switchOff))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color(nsColor: configuration.isOn ? SettingsPalette.knobOn : SettingsPalette.knobOff))
                        .frame(width: size.height - 3, height: size.height - 3)
                        .padding(1.5)
                }
                .frame(width: size.width, height: size.height)
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == SettingsSwitchStyle {
    static var arcSwitch: SettingsSwitchStyle { SettingsSwitchStyle() }
}

private extension View {
    /// Arc's card: a 1 pt hairline round a slightly lighter fill, 5.5 pt corners.
    func settingsCardLook() -> some View {
        frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous).fill(Color(nsColor: SettingsPalette.card)))
            .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .strokeBorder(Color.settingsHairline, lineWidth: 1))
    }
}

/// Rounded card behind grouped rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(spacing: 0) { content }.settingsCardLook() }
}

/// One card row: label on the left, control on the right, 36 pt tall.
struct SettingsCardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.cardRowInset)
        .padding(.vertical, 10)
        .frame(minHeight: SettingsMetrics.cardRowHeight)
    }
}

/// Hairline between card rows, inset 10 like Arc's.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle().fill(Color.settingsHairline)
            .frame(height: 1)
            .padding(.horizontal, SettingsMetrics.cardRowInset)
    }
}

/// 11 pt secondary title above a card ("Your Data and Settings" in Arc's Profiles).
struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.leading, SettingsMetrics.cardRowInset)
            .padding(.bottom, 6)
    }
}

/// 11 pt secondary note under a card.
struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.leading, SettingsMetrics.cardRowInset)
            .padding(.top, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The card around rows with a picture (Arc's Max card); the same look as every card.
struct SettingsFeatureCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(spacing: 0) { content }.settingsCardLook() }
}

/// Arc frames each Max picture in white: 3 pt round an 88×56 tile with 5 pt corners.
struct SettingsPictureFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(width: 88, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
            .accessibilityHidden(true)
    }
}

/// One setting as Arc's Max pane draws a feature: the picture of what it does, its name over a
/// line saying what changes, the control on the right. Only settings that change how Cra looks
/// get a picture; the rest are SettingsPlainRow and SettingsToggleRow. `below` holds what belongs to the setting
/// under its description: a duration menu, a button, a narrower option.
struct SettingsFeatureRow<Picture: View, Trailing: View, Below: View>: View {
    let title: String
    let detail: Text
    @ViewBuilder let picture: Picture
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let below: Below

    init(_ title: String, detail: Text, @ViewBuilder picture: () -> Picture,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.picture = picture()
        self.trailing = trailing()
        self.below = below()
    }

    init(_ title: String, detail: String, @ViewBuilder picture: () -> Picture,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.init(title, detail: Text(detail), picture: picture, trailing: trailing, below: below)
    }

    private var hasPicture: Bool { Picture.self != EmptyView.self }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if hasPicture { SettingsPictureFrame { picture } }
            VStack(alignment: .leading, spacing: hasPicture ? 4 : 2) {
                Text(title).font(.system(size: 13))
                detail
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                below
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.cardRowInset)
        .padding(.vertical, hasPicture ? 10 : 9)
    }
}

/// A setting that doesn't change how Cra looks: no picture, just its name, what it does and the
/// control on the right.
struct SettingsPlainRow<Trailing: View, Below: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let below: Below

    init(_ title: String, detail: String, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        SettingsFeatureRow(title, detail: detail, picture: { EmptyView() }, trailing: { trailing }, below: { below })
    }
}

/// A plain row whose control is a switch. Off and greyed while `enabled` is false.
struct SettingsToggleRow<Below: View>: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var enabled = true
    @ViewBuilder let below: Below

    init(_ title: String, detail: String, isOn: Binding<Bool>, enabled: Bool = true,
         @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.enabled = enabled
        self.below = below()
    }

    var body: some View {
        SettingsSwitchRow(title, detail: detail, isOn: $isOn, enabled: enabled, picture: { EmptyView() }, below: { below })
    }
}

/// A picture row whose control is a switch. Off and greyed while `enabled` is false.
struct SettingsSwitchRow<Picture: View, Below: View>: View {
    let title: String
    let detail: Text
    @Binding var isOn: Bool
    var enabled = true
    @ViewBuilder let picture: Picture
    @ViewBuilder let below: Below

    init(_ title: String, detail: Text, isOn: Binding<Bool>, enabled: Bool = true,
         @ViewBuilder picture: () -> Picture, @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.enabled = enabled
        self.picture = picture()
        self.below = below()
    }

    init(_ title: String, detail: String, isOn: Binding<Bool>, enabled: Bool = true,
         @ViewBuilder picture: () -> Picture, @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.init(title, detail: Text(detail), isOn: isOn, enabled: enabled, picture: picture, below: below)
    }

    var body: some View {
        SettingsFeatureRow(title, detail: detail, picture: { picture }, trailing: {
            Toggle(title, isOn: Binding(get: { isOn && enabled }, set: { isOn = $0 }))
                .toggleStyle(.arcSwitch).labelsHidden()
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
        }, below: { below })
    }
}

extension View {
    /// A plain card row under picture rows starts where their text does (10 + 94 + 14 pt in).
    func settingsTextColumn() -> some View { padding(.leading, 94 + 14) }
}

/// A menu under a setting's description: "After: [12 hours]".
struct SettingsInlinePicker<Value: Hashable, Options: View>: View {
    let label: String
    @Binding var selection: Value
    var enabled = true
    @ViewBuilder let options: Options
    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(enabled ? .primary : .secondary)
            Picker(label, selection: $selection) { options }
                .labelsHidden()
                .fixedSize()
                .disabled(!enabled)
        }
    }
}

private struct SettingsNestedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// A pane shown inside another tab's pane (Tabs' cards in General, Performance in Advanced): its
    /// sections go into the outer pane's scroll view instead of making a second one.
    var settingsNested: Bool {
        get { self[SettingsNestedKey.self] }
        set { self[SettingsNestedKey.self] = newValue }
    }
}

extension View {
    /// This pane's sections join the pane around it (see `settingsNested`).
    func settingsNested() -> some View { environment(\.settingsNested, true) }
}

/// Card-style pane body: 20 pt below the tabs, 64 pt from the sides, scrolling.
struct SettingsCardPane<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsNested) private var nested

    var body: some View {
        if nested {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, SettingsMetrics.paneInset)
                    .padding(.top, SettingsMetrics.paneTop)
                    .padding(.bottom, SettingsMetrics.paneBottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// A one-line card row with a switch, as most of Arc's rows are: the name on the left, the switch on the right.
struct SettingsSwitchLine<Note: View>: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true
    @ViewBuilder let note: Note

    init(_ title: String, isOn: Binding<Bool>, enabled: Bool = true, @ViewBuilder note: () -> Note = { EmptyView() }) {
        self.title = title
        self._isOn = isOn
        self.enabled = enabled
        self.note = note()
    }

    var body: some View {
        SettingsCardRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                note
            }
        } trailing: {
            Toggle(title, isOn: Binding(get: { isOn && enabled }, set: { isOn = $0 }))
                .toggleStyle(.arcSwitch).labelsHidden()
                .disabled(!enabled).opacity(enabled ? 1 : 0.5)
        }
    }
}

/// Arc's rule between a pane's groups (Links): a hairline across the pane's width.
struct SettingsRule: View {
    var body: some View { Rectangle().fill(Color.settingsHairline).frame(height: 1) }
}

/// A line of body text over a card (Arc's Links and Max panes explain themselves in 13 pt before the rows).
struct SettingsBlurb: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SettingsMetrics.cardRowInset)
    }
}

/// The picture bands at the top of Arc's Max and Links panes end in a wavy edge, a scallop every 17 pt.
struct SettingsScallopedBand: Shape {
    var wave: CGFloat = 4
    var period: CGFloat = 17
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let base = rect.maxY - wave
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: base))
        var x = rect.maxX
        while x > rect.minX {
            let next = max(x - period, rect.minX)
            p.addQuadCurve(to: CGPoint(x: next, y: base), control: CGPoint(x: (x + next) / 2, y: base + wave * 2))
            x = next
        }
        p.closeSubpath()
        return p
    }
}

/// A row of Arc's Advanced tab: a 20 pt coloured tile with its glyph, the name, the switch.
struct SettingsTileRow: View {
    enum Tile {
        case blue, green, red, purple
        var color: Color {
            switch self {
            case .blue: return Color(.sRGB, red: 0.2, green: 0.5, blue: 1)
            case .green: return Color(.sRGB, red: 0.3, green: 0.8, blue: 0.4)
            case .red: return Color(.sRGB, red: 0.93, green: 0.3, blue: 0.28)
            case .purple: return Color(.sRGB, red: 0.8, green: 0.3, blue: 0.9)
            }
        }
    }

    let title: String
    let symbol: String
    let tile: Tile
    @Binding var isOn: Bool

    init(_ title: String, symbol: String, tile: Tile, isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        self.tile = tile
        self._isOn = isOn
    }

    var body: some View {
        SettingsCardRow {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tile.color))
                Text(title).font(.system(size: 13))
            }
        } trailing: {
            Toggle(title, isOn: $isOn).toggleStyle(.arcSwitch).labelsHidden()
        }
    }
}
