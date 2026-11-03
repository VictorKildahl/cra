import CoreGraphics

/// Where Arc's Peek card and its buttons go in a browser window (y up, as in AppKit).
///
/// Arc 1.171 (offline Arc, 1728 × 1084 pt window with a 347 pt sidebar, AX frames, 3 Nov 2026): the
/// card is centred on the area right of the sidebar (sidebar edge to the window's edge, not the page
/// card's), 80 % of its width (1105 of 1381 pt), 12 pt in from the window's top and bottom. Close,
/// Expand and Add To Split are 34 × 33 pt round buttons in a column 13 pt right of the card, the
/// first 7 pt below its top, 43.5 pt apart. The page behind fades to 28 %, the card has 8 pt corners
/// and a 32 pt bar. It opens from the area's full size to its own in 0.12 s and closes the same way
/// back in 0.22 s, fading as it goes.
public enum PeekLayout {
    public static let widthFraction: CGFloat = 0.8
    public static let verticalInset: CGFloat = 12
    public static let cornerRadius: CGFloat = 8
    public static let barHeight: CGFloat = 32
    public static let buttonSize = CGSize(width: 34, height: 33)
    public static let buttonGap: CGFloat = 13
    public static let buttonTop: CGFloat = 7
    public static let buttonPitch: CGFloat = 43.5
    public static let buttonCount = 3
    /// The page under a Peek (Arc: 233/240/254 → 178/172/151 over the window's background).
    public static let pageAlpha: CGFloat = 0.28
    public static let openDuration: Double = 0.12
    public static let closeDuration: Double = 0.22

    /// The area a Peek covers: right of the sidebar (`contentMinX`, window coordinates) to the
    /// window's right edge, its full height.
    public static func area(window: CGSize, contentMinX: CGFloat) -> CGRect {
        CGRect(x: contentMinX, y: 0, width: max(0, window.width - contentMinX), height: window.height)
    }

    public static func card(in area: CGRect) -> CGRect {
        let w = (area.width * widthFraction).rounded()
        return CGRect(x: (area.midX - w / 2).rounded(), y: area.minY + verticalInset,
                      width: w, height: max(0, area.height - 2 * verticalInset))
    }

    /// The column's buttons, top first, beside `card`.
    public static func buttons(beside card: CGRect) -> [CGRect] {
        (0..<buttonCount).map { i in
            let top = card.maxY - buttonTop - CGFloat(i) * buttonPitch
            return CGRect(x: card.maxX + buttonGap, y: ((top - buttonSize.height) * 2).rounded() / 2,
                          width: buttonSize.width, height: buttonSize.height)
        }
    }

    /// The column itself: all the buttons in one frame.
    public static func column(beside card: CGRect) -> CGRect {
        buttons(beside: card).reduce(CGRect.null) { $0.union($1) }
    }
}
