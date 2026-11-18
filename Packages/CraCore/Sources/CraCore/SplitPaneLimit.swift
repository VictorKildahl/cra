import Foundation

/// How many panes one split holds. Arc's split view holds four, and so does Cra unless Settings ▸
/// Links ▸ "More than four panes in a split" is on (GitHub #498, off by default; not in Arc): then
/// eight. Every way of adding a pane asks this, so they all stop at the same count (a sidebar
/// drop, the page drop, ⌃⇧=, Open Link in Split View, ⌥-click, picked tabs, a middle click).
public enum SplitPaneLimit {
    /// Arc's most panes in one split.
    public static let arc = 4
    /// The most with the setting on. The reporter of #498 had used six; eight side by side still
    /// leaves each pane Arc's 220 pt minimum on a 1920 pt wide window, and stacked they share it.
    public static let more = 8

    /// The most panes a split holds, with "More than four panes in a split" `morePanes`.
    public static func maximum(morePanes: Bool) -> Int { morePanes ? more : arc }

    /// Whether a split of `panes` takes one more.
    public static func canAdd(to panes: Int, morePanes: Bool) -> Bool { panes < maximum(morePanes: morePanes) }
}
