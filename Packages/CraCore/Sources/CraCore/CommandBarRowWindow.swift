import Foundation

/// The ⌘T bar's list as Arc shows it (#805): five rows in view, more behind them. The arrows walk
/// past the fifth row and the list scrolls a row at a time to keep the selected one in view; past
/// the last row the selection wraps to the first, and the list back to the top.
public enum CommandBarRowWindow {
    /// Rows in view, as Arc's bar is sized for (the banner takes the last place while it shows).
    public static let visibleRows = 5
    /// Rows the bar holds for a query, the completion and typed rows among them: Arc's
    /// `CommandBar.SuggestionConstants.MaxSuggestions`. Fifteen in the reporter's recording of Arc (#805):
    /// ↓ held walks rows 0, 3, 6, 9, 12 and wraps to 0, ↑ on the first row selects the fifteenth with
    /// rows 10–14 in view, and a page that matched one letter less was not among them.
    public static let maxSuggestions = 15

    /// Rows in view for `count` rows, with or without the search-suggestions banner below them.
    public static func shown(count: Int, banner: Bool) -> Int {
        min(count, max(0, visibleRows - (banner ? 1 : 0)))
    }

    /// The first row in view, so `selected` is: the list stays where it was (`previous`) while the
    /// selected row is in view and otherwise moves as little as it takes, so a step past the bottom
    /// scrolls one row and a wrap to the top or the bottom brings that end into view.
    public static func first(selected: Int, count: Int, shown: Int, previous: Int) -> Int {
        guard shown > 0, count > shown else { return 0 }
        let last = count - shown
        var first = min(max(0, previous), last)
        let s = min(max(0, selected), count - 1)
        if s < first { first = s }
        if s >= first + shown { first = s - shown + 1 }
        return min(first, last)
    }
}
