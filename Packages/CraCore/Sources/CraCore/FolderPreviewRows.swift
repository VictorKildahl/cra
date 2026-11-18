import CoreGraphics

/// The rows of a folder's preview (Arc 1.171, docs/arc-reverse-engineering.md "Folder previews"):
/// the first 4 pt under the search field's hairline, one every 45 pt, scrolling past six.
/// One row at a time is under the pointer, and the list works out which from where the pointer is
/// each time either moves. Rows that tracked the pointer themselves kept their highlight when the
/// list scrolled under a still pointer, as AppKit sent no exit, and lit several at once (#544).
public enum FolderPreviewRows {
    public static let listInset: CGFloat = 4
    public static let rowPitch: CGFloat = 45

    /// The row under the pointer, `y` points down the list's shown part with the list scrolled
    /// `offset` points: nil above the first row, below the last, or off the list.
    public static func row(atY y: CGFloat, offset: CGFloat, height: CGFloat, count: Int) -> Int? {
        guard y >= 0, y < height else { return nil }
        let down = y + offset - listInset
        guard down >= 0 else { return nil }
        let i = Int((down / rowPitch).rounded(.down))
        return i < count ? i : nil
    }
}
