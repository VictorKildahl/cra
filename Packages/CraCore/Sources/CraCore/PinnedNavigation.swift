import Foundation

/// Arc 1.171 keeps a pinned tab on its site (PinnedTabNavigationProfile, recorded live, GitHub #139):
/// an address typed into it (⌘L) on another host opens as a new Today tab; the same host loads in place.
/// pin.lvh.me → away.lvh.me opened a new tab, so it compares hosts, not sites.
public enum PinnedNavigation {
    public static func typedURLOpensNewTab(_ typed: String, from current: String) -> Bool {
        guard let to = URL(string: typed)?.host?.lowercased() else { return false }
        return to != URL(string: current)?.host?.lowercased()
    }

    /// A link that opens Peek (Settings ▸ Tabs ▸ Links) leads to another host: pin.lvh.me →
    /// away.lvh.me peeked in Arc, though both are one site.
    public static func linkLeavesHost(_ link: String, from page: String) -> Bool {
        guard let to = URL(string: link)?.host?.lowercased(), !to.isEmpty else { return false }
        return to != URL(string: page)?.host?.lowercased()
    }
}
