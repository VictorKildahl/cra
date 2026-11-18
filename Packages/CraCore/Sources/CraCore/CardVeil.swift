import Foundation

/// The white veil a card with no page in it lays over the space's colour.
///
/// A window with no tab shows a white card, in the same inset and with the same shadow as a
/// page's: measured on Arc screenshots in light and dark spaces (17 Nov 2026), the card is the
/// colour beside it under white at about 0.65 to 0.68 light and 0.10 dark. An empty pane (a tab
/// whose page isn't there) is fainter: the gradient plus about +9/+11/+12 per channel, a white
/// veil at about 0.2 (Arc 1.170, Victor theme, 2x).
public enum CardVeil {
    /// - Parameters:
    ///   - noTab: the window's card with no tab selected, rather than a pane's card.
    ///   - dark: the space's theme is on its dark half.
    public static func white(noTab: Bool, dark: Bool) -> Double {
        noTab ? (dark ? 0.10 : 0.65) : (dark ? 0.08 : 0.2)
    }
}
