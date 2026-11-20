import Foundation

/// What picking an open tab in the command bar does while the bar fills a split's new, empty pane
/// (Add Split View, ⌃⇧=; GitHub #645). Arc brings the tab into the split: it takes the empty pane's
/// place, as a tab dropped on a pane does (`SidebarStore.addToSplit(_:tabID:at:replacing:)`). Cra
/// switched to the tab instead and left the empty pane behind.
public enum SplitPanePick {
    public enum Outcome: Equatable, Sendable {
        /// Not filling a pane: the bar switches to the tab, as ⌘T's row does.
        case switchTo
        /// The tab is already one of the split's panes: it becomes the open pane and the empty one goes.
        case selectPane(dropping: UUID)
        /// The tab takes the empty pane's place in the split.
        case join(replacing: UUID)
    }

    /// - Parameters:
    ///   - picked: the open tab the row stands for.
    ///   - emptyPane: the selected tab when it is a split's empty pane waiting for a page, else nil.
    ///   - panes: the split's panes (the selected tab's `paneTabIDs`).
    ///   - sameProfile: the picked tab's page is in the empty pane's profile. A page can't move to another
    ///     profile's space, so a tab from one is switched to, as before.
    public static func of(picked: UUID, emptyPane: UUID?, panes: [UUID], sameProfile: Bool) -> Outcome {
        guard let emptyPane, picked != emptyPane else { return .switchTo }
        if panes.contains(picked) { return .selectPane(dropping: emptyPane) }
        return sameProfile ? .join(replacing: emptyPane) : .switchTo
    }
}
