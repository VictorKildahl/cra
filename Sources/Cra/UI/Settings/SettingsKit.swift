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
    /// Form panes (Tabs, Advanced): labels end 178.5 pt into the content, controls start at 202.
    static let formLabelWidth: CGFloat = 178.5
    static let formControlX: CGFloat = 202
    static let formTop: CGFloat = 31
    static let formGroupSpacing: CGFloat = 14
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

/// Dia's coloured 20 pt rounded-square glyph in front of a Privacy row.
struct SettingsGlyph: View {
    let symbol: String
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
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

/// Form-style pane body (Dia's Tabs and Advanced): right-aligned labels, left-aligned controls.
/// Scrolls like the card panes: the window has a fixed height, and without a scroll view a
/// form taller than it squeezed its rows on top of each other.
struct SettingsFormPane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SettingsMetrics.formGroupSpacing) { content }
                .padding(.top, SettingsMetrics.formTop)
                .padding(.trailing, SettingsMetrics.paneInset)
                .padding(.bottom, SettingsMetrics.paneInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
    }
}

/// One labelled group of a form pane ("General:" + checkboxes).
struct SettingsFormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: SettingsMetrics.formLabelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) { content }   // 16 pt checkboxes on Dia's 24 pt pitch
                .padding(.leading, SettingsMetrics.formControlX - SettingsMetrics.formLabelWidth)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30, alignment: .top)
    }
}

/// Standard checkbox with 13 pt text, the way Dia's form panes draw theirs.
struct SettingsCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.checkbox).font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)   // long titles wrap instead of truncating
    }
}
