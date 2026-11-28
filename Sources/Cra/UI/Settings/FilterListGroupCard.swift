import SwiftUI

struct FilterListGroupCard<Rows: View>: View {
    let title: String
    let selected: Int
    let total: Int
    @State var isExpanded: Bool
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        let summary = "\(selected) of \(total) selected"
        SettingsFeatureCard {
            Button { isExpanded.toggle() } label: {
                SettingsCardRow {
                    Text(title).fontWeight(.medium)
                } trailing: {
                    Text(summary).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded, " + summary : "Collapsed, " + summary)
            if isExpanded { rows() }
        }
    }
}
