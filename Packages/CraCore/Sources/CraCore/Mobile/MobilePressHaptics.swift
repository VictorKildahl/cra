import Foundation

/// The tick the bottom bar's buttons give under a finger (#675). Arc Search's buttons tap back twice, as the
/// reporter of #675 describes them from using it: once as the finger comes down on the button, again as it lets go.
/// Cra's gave nothing until the action ran, and the New Tab pill nothing at all.
public enum MobilePressHaptics {
    public enum Tick: Equatable, Sendable {
        /// The finger came down on the button: a light impact.
        case press
        /// It let go (or slid off): a softer one.
        case release
    }

    /// The bar's buttons that tick, by accessibility identifier: the tab stack, the New Tab pill and the menu
    /// button on a page; Spaces and Settings in the tab switcher.
    public static let barButtons: Set<String> = ["bar-tabs", "bar-search", "bar-menu", "bar-spaces", "bar-settings"]

    /// The tick for a button's highlight going from `was` to `now`: one as it lights up, one as it goes out,
    /// none while it stays as it is (UIKit sets the highlight again as a finger moves on the button).
    public static func tick(from was: Bool, to now: Bool) -> Tick? {
        guard was != now else { return nil }
        return now ? .press : .release
    }
}
