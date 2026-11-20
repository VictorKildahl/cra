import Foundation

/// Where a Peek's address and its ← → ↻ live (GitHub #648).
///
/// Arc 1.174 with the address in the sidebar (vamshikrishna83, live, 20 Nov 2026): a Peek's card has no
/// bar of its own. The sidebar's address field shows the Peek's page while it is in front, and Close,
/// Expand and Add To Split stay beside the card. With Arc's toolbar shown the card keeps its 32 pt bar
/// (Arc 1.171, offline, 3 Nov 2026: `PeekLayout`).
///
/// Cra keeps one thing of its own: Settings ▸ Links ▸ "Hide the Peek toolbar until you need it"
/// (#493) is a bar that slides in at the card's top, so with that switch on the card keeps it, put away
/// until the pointer asks for it, whichever way the address is placed.
public enum PeekAddress {
    /// Whether the Peek's card carries a bar of its own. An easel in Peek never has one (Arc 1.171).
    public static func cardHasBar(showToolbar: Bool, autoHidePeekToolbar: Bool, easel: Bool) -> Bool {
        !easel && (showToolbar || autoHidePeekToolbar)
    }

    /// The page in a Peek, as the sidebar's address row needs it.
    public struct Page: Equatable, Sendable {
        /// The Peek it comes from: an edit in place ends when another Peek, or the tab, takes the field.
        public var id: UUID
        public var url: String
        public var canGoBack: Bool
        public var canGoForward: Bool
        public var isLoading: Bool

        public init(id: UUID, url: String, canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
            self.id = id
            self.url = url
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
            self.isLoading = isLoading
        }
    }

    /// The Peek the sidebar's address row stands for, or nil for the tab. `peek` is the one on screen
    /// over the window (not waiting behind another tab, not closing). Only while the address is in the
    /// sidebar: a toolbar's address belongs to the tab's page, and the card has its own bar then.
    public static func sidebarShows(peek: Page?, showToolbar: Bool) -> Page? {
        showToolbar ? nil : peek
    }

    /// The field's accessories while it shows a Peek: Copy Link, which copies the Peek's address.
    /// Pinned extensions and the Site Control Center act on the tab's page, so they wait for the Peek
    /// to go rather than act on a page the field doesn't show.
    public static func fieldAccessories(_ items: [ToolbarComposition.Item]) -> [ToolbarComposition.Item] {
        items.filter { $0 == .copyURL }
    }
}
