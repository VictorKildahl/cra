import CoreGraphics

/// Where the loading bar goes and which ink it takes (GitHub #548).
///
/// Arc keeps the bar in one place whatever the card does: 4 pt tall, 3–7 pt below the window's top
/// edge, centred over the card. In a window that is the middle of the 10 pt margin above the card;
/// in full screen with the sidebar hidden the card fills the screen, and the bar lies over the
/// card's top, on its toolbar, in white over Arc's dark blue bar. Measured on Arc 1.172.2, 18 Nov
/// 2026, 2x window captures through a reload of a slow local page: window (sidebar shown, then
/// hidden), full screen with the sidebar shown, and full screen with it hidden, where the bar's
/// rows were the same 6–13 px from the top as in the window. Arc keeps its toolbar while the sidebar
/// is hidden (View ▸ Hide Toolbar changed nothing there), so its bar is never over the page itself.
///
/// Cra can hide the toolbar, or float it, with the card filling the window (edge to edge #24, or
/// full screen), so its bar can lie on the page. The ink then follows what is under it, by the
/// toolbar's own rule (PaneToolbarView: a colour lighter than 0.6 luminance takes dark ink), or a
/// white bar would vanish on a white page.
public extension LoadingIndicator {
    /// The band at the window's top the bar is centred in: the margin above a card in its inset.
    static let topBand: Double = 10

    /// What lies under the bar.
    enum Ground: Equatable, Sendable {
        /// The window's margin above the card, in the space's theme.
        case margin
        /// The card's toolbar: its colour ("#RRGGBB"), nil for Arc's white bar (ToolbarColor).
        case toolbar(String?)
        /// Arc's developer bar, which always takes near-white ink.
        case developerBar
        /// The page itself: its background ("#RRGGBB"), nil before it reported one.
        case page(String?)
    }

    /// The bar's frame in the window (y up): the track's width plus a point each side, `topBand`
    /// tall at the window's top, centred over the card.
    static func frame(window: CGRect, card: CGRect) -> CGRect {
        let width = trackWidth + 2
        return CGRect(x: (card.midX - width / 2).rounded(), y: window.maxY - topBand, width: width, height: topBand)
    }

    /// Whether the bar lies over the card rather than in the margin above it: the card reaches
    /// into the band at the window's top.
    static func overCard(window: CGRect, card: CGRect) -> Bool {
        window.maxY - card.maxY < topBand
    }

    /// Whether the bar takes white ink. `themeDark`: the window's theme (the margin's colour);
    /// `canvasDark`: the appearance pages get, for a page that has reported no colour yet.
    static func lightInk(on ground: Ground, themeDark: Bool, canvasDark: Bool) -> Bool {
        switch ground {
        case .margin: return themeDark
        case .developerBar: return true
        case .toolbar(let hex): return (hex.flatMap(HexColor.luminance) ?? 1) <= 0.6
        case .page(let hex): return hex.flatMap(HexColor.luminance).map { $0 <= 0.6 } ?? canvasDark
        }
    }
}
