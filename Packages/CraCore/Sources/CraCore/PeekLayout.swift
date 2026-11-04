import CoreGraphics

/// Where Arc's Peek card and its buttons go in a browser window (y up, as in AppKit).
///
/// Arc 1.171 (offline Arc, 1728 × 1084 pt window with a 347 pt sidebar, AX frames, 3 Nov 2026): the
/// card is centred on the area right of the sidebar (sidebar edge to the window's edge, not the page
/// card's), 80 % of its width (1105 of 1381 pt), 12 pt in from the window's top and bottom. Close,
/// Expand and Add To Split are 34 × 33 pt round buttons in a column 13 pt right of the card, the
/// first 7 pt below its top, 43.5 pt apart. The page behind fades to 28 %, the card has 8 pt corners
/// and a 32 pt bar. It opens from the area's full size to its own and closes the same way back,
/// fading as it goes (the timings below).
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
    /// Arc's open, measured frame by frame at 60 fps (3 Nov 2026): the card's opacity reaches 1 in
    /// 0.075 s; its scale, from the whole area (1 / widthFraction) to 1 about its centre, follows an
    /// ease-out cubic over 0.205 s starting a frame in; the page fades to `pageAlpha` on an ease-out
    /// cubic over 0.18 s. The buttons ride the card's top-right corner and fade with it.
    public static let openFadeDuration: Double = 0.075
    public static let openScaleDelay: Double = 0.016
    public static let openScaleDuration: Double = 0.205
    public static let openVeilDuration: Double = 0.18
    /// Arc's close: back out to the whole area in 0.12 s (near linear), fading from 0.07 s for
    /// 0.09 s, while the page comes back over 0.2 s.
    public static let closeScaleDuration: Double = 0.12
    public static let closeFadeDelay: Double = 0.07
    public static let closeFadeDuration: Double = 0.09
    public static let closeVeilDuration: Double = 0.2
    /// The scale that makes the card cover the whole area's width.
    public static let areaScale: CGFloat = 1 / widthFraction

    /// How far the card's top-right corner (and the buttons with it) is from its place while the
    /// card is drawn at `scale` about its centre.
    public static func cornerShift(card: CGRect, scale: CGFloat) -> CGVector {
        CGVector(dx: (scale - 1) * card.width / 2, dy: (scale - 1) * card.height / 2)
    }

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
