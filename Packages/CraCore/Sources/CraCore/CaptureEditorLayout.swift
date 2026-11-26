import CoreGraphics

/// Arc's image editor for a capture (Capture ▸ Edit, `EaselUI.ModalImageEditor`; Arc 1.174 measured live on
/// 26 Nov 2026 at 2x, #851): the page goes dark under a black veil, the capture shows in a card in the middle, a
/// point per pixel, with Easel's seven tools (no Duplicate) at its bottom left. What is drawn on it goes into the
/// capture when a click lands on the dark page around the card; Escape leaves the editor open.
public enum CaptureEditorLayout {
    /// 255 → 57 under it.
    public static let veil: CGFloat = 0.776
    public static let cornerRadius: CGFloat = 10.5
    /// The toolbar's distance from the card's left and bottom edges.
    public static let toolbarInset: CGFloat = 12
    /// Room kept round a capture too big for the page (not measured: Arc's capture was smaller than the page).
    public static let margin: CGFloat = 40
    /// Easel's toolbar with its seven tools and no Duplicate: 272 pt, as measured.
    public static var toolbarWidth: CGFloat { EaselToolbarLayout.toolsWidth }

    /// The card, in the page's coordinates (top left origin): the capture at a point per pixel, shrunk to fit inside
    /// `margin` if it is bigger than the page, never smaller than the toolbar needs, centred.
    public static func card(pixels: CGSize, in page: CGSize) -> CGRect {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let room = CGSize(width: max(1, page.width - 2 * margin), height: max(1, page.height - 2 * margin))
        let fit = min(1, room.width / pixels.width, room.height / pixels.height)
        let minW = toolbarWidth + 2 * toolbarInset, minH = EaselToolbarLayout.height + 2 * toolbarInset
        let size = CGSize(width: max(minW, (pixels.width * fit).rounded()), height: max(minH, (pixels.height * fit).rounded()))
        return CGRect(x: (page.width - size.width) / 2, y: (page.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// The toolbar, in the card's coordinates (top left origin).
    public static func toolbar(in card: CGSize) -> CGRect {
        CGRect(x: toolbarInset, y: card.height - toolbarInset - EaselToolbarLayout.height,
               width: toolbarWidth, height: EaselToolbarLayout.height)
    }
}
