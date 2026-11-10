import SwiftUI

/// Geometry of Dia 1.54.2's Settings window, measured from window captures and the
/// accessibility tree (docs/arc-reverse-engineering.md "Dia Settings window").
enum SettingsMetrics {
    static let windowSize = CGSize(width: 778, height: 509)
    static let sidebarWidth: CGFloat = 204
    static let toolbarHeight: CGFloat = 52
    static let navPillSize = CGSize(width: 69, height: 38)
    /// Card panes: cards sit 21 pt from the content edges, 20 pt below the toolbar.
    static let paneInset: CGFloat = 21
    static let paneTop: CGFloat = 20
    static let cardCorner: CGFloat = 12
    static let cardRowInset: CGFloat = 10
    static let cardRowHeight: CGFloat = 43
}

/// Rounded card behind grouped rows (white 7% over the window in dark mode).
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.6)))
    }
}

/// One card row: label on the left, control on the right, 43 pt tall.
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
        .padding(.vertical, 10.5)
        .frame(minHeight: SettingsMetrics.cardRowHeight)
    }
}

/// Hairline between card rows, inset 10 like Dia's.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, SettingsMetrics.cardRowInset)
    }
}

/// Bold 13 pt section title above a card ("Content blocking", "Data").
struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold))
            .padding(.leading, 8)
            .padding(.bottom, 5.5)
    }
}

/// 11 pt secondary note under a card.
struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The card around picture rows (Arc's Max card): a hairline border on a lighter fill, rows
/// split by hairlines.
struct SettingsFeatureCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
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
                Text(title).font(.system(size: hasPicture ? 14 : 13))
                detail
                    .font(.system(size: hasPicture ? 12 : 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                below
                    .font(.system(size: hasPicture ? 12 : 11))
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 10)
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
                .toggleStyle(.switch).labelsHidden()
                .disabled(!enabled)
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

/// Card-style pane body: 20 pt below the toolbar, 21 pt from the sides.
struct SettingsCardPane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, SettingsMetrics.paneInset)
                .padding(.top, SettingsMetrics.paneTop)
                .padding(.bottom, SettingsMetrics.paneInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}
