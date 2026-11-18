import CoreGraphics

/// A split's card in the tab switcher (#554), measured on Arc 1.172 (18 Nov 2026, 2× capture):
/// the thumbnail's rectangle becomes a dark frame and each pane's own thumbnail sits in it, 4 pt
/// in from its edges and 4 pt apart, as wide as the pane's share of the split. Each pane's
/// favicon is centred under its thumbnail; no titles.
public enum SwitcherSplitLayout {
    public static let inset: CGFloat = 4
    public static let gap: CGFloat = 4

    /// The panes' rectangles inside a frame of `size` (origin top left), on half points so
    /// they land on device pixels at 2×. `widths` are the panes' shares of the split.
    public static func paneFrames(in size: CGSize, widths: [CGFloat]) -> [CGRect] {
        guard !widths.isEmpty else { return [] }
        let total = widths.reduce(0) { $0 + max($1, 0) }
        let shares = total > 0 ? widths.map { max($0, 0) / total } : widths.map { _ in 1 / CGFloat(widths.count) }
        let inner = size.width - 2 * inset - gap * CGFloat(widths.count - 1)
        let height = size.height - 2 * inset
        func half(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        var frames: [CGRect] = []
        var start: CGFloat = 0
        for (i, share) in shares.enumerated() {
            let end = i == shares.count - 1 ? inner : start + inner * share
            let x0 = half(inset + start + gap * CGFloat(i)), x1 = half(inset + end + gap * CGFloat(i))
            frames.append(CGRect(x: x0, y: inset, width: max(0, x1 - x0), height: height))
            start = end
        }
        return frames
    }

    /// The width-to-height ratio a pane's thumbnail is taken at, so it fills its place on the card.
    public static func paneAspect(in size: CGSize, widths: [CGFloat], pane: Int) -> CGFloat? {
        let frames = paneFrames(in: size, widths: widths)
        guard frames.indices.contains(pane), frames[pane].height > 0, frames[pane].width > 0 else { return nil }
        return frames[pane].width / frames[pane].height
    }
}
