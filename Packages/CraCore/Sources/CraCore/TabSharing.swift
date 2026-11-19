/// A call sharing a tab (a page's getDisplayMedia, or casting a tab), the way Arc shows it, measured
/// from a recording of Arc 1.173 with Google Meet (X DM, 19 Nov 2026):
/// - the shared tab's sidebar row has a 2 pt yellow ring;
/// - its page card has the same ring while it's on screen, the card's own split-view focus ring
///   giving way to it;
/// - hovering any other tab the call can switch to shows Arc's "Share this tab instead" button
///   (rectangle.inset.filled.and.person.filled), a 24 pt square against the close button. A click
///   shares that tab and shows it.
/// The tab doing the sharing (the call) keeps its red recording dot and gets no button.
public enum TabSharing {
    /// The rings' width, on the row and on the card.
    public static let ringWidth: Double = 2
    /// Arc's tooltip on the button.
    public static let shareInsteadHelp = "Share this tab instead"
    public static let shareInsteadSymbol = "rectangle.inset.filled.and.person.filled"

    /// What a page card's ring shows.
    public enum PaneRing: Equatable, Sendable {
        case none
        /// The focused pane of several (Arc's focusBorderLayer, in the space's colour).
        case focus
        /// The page a call shares: yellow.
        case shared
    }

    /// `panes` cards in the window; `focused` is this one's tab the focused (or drop-target) pane;
    /// `shared` is its tab the one a call shares. A page in full screen has no card, so no ring.
    public static func paneRing(panes: Int, focused: Bool, shared: Bool, fullscreen: Bool) -> PaneRing {
        if fullscreen { return .none }
        if shared { return .shared }
        return panes > 1 && focused ? .focus : .none
    }

    /// Whether a tab's row shows the button: while hovered (and not being renamed), for a tab the
    /// call can switch to. Chrome offers no switch to the shared tab itself or to the call's tab.
    public static func showsShareInstead(hovered: Bool, editing: Bool, canShareInstead: Bool, shared: Bool) -> Bool {
        hovered && !editing && canShareInstead && !shared
    }
}
