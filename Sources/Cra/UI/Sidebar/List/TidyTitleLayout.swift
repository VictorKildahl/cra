import AppKit

/// A snapshot of the native row's current title box, without its text-field padding.
@MainActor
struct TidyTitleLayout {
    let width: CGFloat
    let font: NSFont

    init(label: NSTextField, inset: CGFloat) {
        width = max(0, label.frame.width - 2 * inset)
        font = label.font ?? .systemFont(ofSize: 14)
    }

    private init(width: CGFloat, font: NSFont) {
        self.width = width
        self.font = font
    }

    /// An offscreen/unmaterialized row has no reliable width; keep the smallest candidate.
    static var fallback: Self { Self(width: 0, font: .systemFont(ofSize: 14)) }

    func select(_ candidates: [String], shown: String) -> String? {
        let measured = candidates.map {
            (title: $0, width: Double(($0 as NSString).size(withAttributes: [.font: font]).width))
        }
        return TidyTitles.select(measured, availableWidth: Double(width), shown: shown)
    }
}
