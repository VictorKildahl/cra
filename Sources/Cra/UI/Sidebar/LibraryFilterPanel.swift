import SwiftUI

/// Arc's Filter panel on Library ▸ Archived Tabs and Downloads (Arc 1.172.1, 8 Nov 2026, 2x stills):
/// it takes the search row's place: the title ("Filter Archived Tabs", 15 pt semibold, 12 pt in) and
/// a Done pill (59 × 36 pt); then each question (12.5 pt semibold, faded) over a wrapping row of
/// 33 pt chips, 6 pt apart, light until picked, dark with white text once picked.
struct LibraryFilterPanel: View {
    struct Chip: Identifiable {
        var id: String
        var label: String
        var icon: String? = nil
        var on: Bool
    }

    struct Section: Identifiable {
        var id: String { title }
        var title: String
        var chips: [Chip]
    }

    let title: String
    let sections: [Section]
    /// The list's width: the chips wrap within it.
    var width: CGFloat = 300
    let dark: Bool
    let toggle: (String) -> Void
    let done: () -> Void

    private var ink: Color { dark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink.opacity(0.78))
                Spacer()
                Button(action: done) {
                    Text("Done").font(.system(size: 14, weight: .medium)).foregroundStyle(ink.opacity(0.78))
                        .frame(width: 59, height: 36)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .frame(height: 36)
            .padding(.top, 10)
            ForEach(sections) { s in
                Text(s.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ink.opacity(0.55))
                    .padding(.top, 16).padding(.bottom, 7)
                FlowRow(spacing: 6) {
                    ForEach(s.chips) { c in
                        Button { toggle(c.id) } label: {
                            HStack(spacing: 5) {
                                if let icon = c.icon { Text(icon).font(.system(size: 13)) }
                                Text(c.label).font(.system(size: 14, weight: c.on ? .semibold : .regular))
                            }
                            .foregroundStyle(c.on ? (dark ? Color.black : .white) : ink.opacity(0.7))
                            .padding(.horizontal, 12).frame(height: 33)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(c.on ? ink.opacity(dark ? 0.85 : 0.68) : ink.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(c.on ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.bottom, 4)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Chips left to right, onto the next line when the row is full.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, s.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
