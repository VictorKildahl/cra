import AppKit
import SwiftUI

/// What an import left out of one tile's kind, opened from that tile: each item's title, address
/// and reason, and Copy for the whole list as plain text.
struct SkippedList: View {
    let report: ImportReport
    let c: ImportColors
    @State private var copyHover = false
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(report.skipped.count) not imported").font(.system(size: 14, weight: .medium)).foregroundStyle(c.title)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.plainText, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                        Text("Copy").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(copyHover ? c.title : c.body)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { copyHover = $0 }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(report.skipped.indices, id: \.self) { i in
                        let skip = report.skipped[i]
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skip.title.isEmpty ? skip.url : skip.title).font(.system(size: 13, weight: .medium)).foregroundStyle(c.title).lineLimit(1)
                            if !skip.url.isEmpty {
                                Text(skip.url).font(.system(size: 11)).foregroundStyle(c.caption).lineLimit(1).truncationMode(.middle)
                            }
                            Text(skip.reason.text).font(.system(size: 11)).foregroundStyle(c.body).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .frame(height: min(max(rowsHeight, 1), 280))
        }
        .padding(16)
        .frame(width: 340)
    }
}
