import Foundation

/// Arc's Blank Window (File ▸ Blank Window, ⌃⌘N; GitHub #220): a normal-profile window whose
/// sidebar is its own. Arc keeps it as a `standalone` sidebar container keyed by the window
/// (`sidebarContext: standalone` in StorableWindows.json, `{standalone: <window id>}` in
/// StorableSidebar.json) beside the global one every other window shares. Seen in Arc 1.172
/// (6 Nov 2026): the header reads "This Window", there are no favorites, no pinned section and no
/// space icons, the command bar opens, and closing the window removes its container. Its + does
/// nothing. "Move to…" lists the spaces; picking one moves the window's tabs to the top of that
/// space's Today, opens its open tab in the main window and closes the Blank Window.
/// Cra gives the window a space of its own that no space list shows (`Space.standaloneWindowID`).
public enum BlankWindow {
    /// The sidebar header, Arc's words.
    public static let title = "This Window"

    /// Arc's theme-less window: grey-violet while macOS is dark, lavender-white while it is light
    /// (Arc follows the system). Fitted on window captures (inactive): dark, Arc's sidebar is #313246
    /// at the top and #363247 at the bottom, Cra draws #303145 and #363548; light, Arc's is #E3E3F4 and
    /// #E9E7F1, Cra draws #E5E5F3 and #EAE9F3. (Arc's empty page area differs from Cra's: #4F4B5D
    /// against #3A3B4E dark, #F8F7FA against #E0DFEE light.)
    public static let theme = SpaceTheme(
        light: SpaceTheme(colors: ["#DCDBF3", "#E6E3EF"], intensity: 0.9, noise: 0.08, appearance: "light"),
        dark: SpaceTheme(colors: ["#222337", "#2B273A"], intensity: 0.9, noise: 0.08, appearance: "dark"))

    /// The space a new Blank Window shows, with its three containers.
    public static func space(window: UUID, at date: Date, id: UUID = UUID()) -> (space: Space, containers: [SidebarItem]) {
        let favorites = SidebarItem.container(.favorites(spaceID: id))
        let pinned = SidebarItem.container(.pinned(spaceID: id))
        let today = SidebarItem.container(.today(spaceID: id))
        let space = Space(id: id, title: title, emoji: "", theme: theme, favoritesContainerID: favorites.id,
                          pinnedContainerID: pinned.id, todayContainerID: today.id, createdAt: date,
                          standaloneWindowID: window)
        return (space, [favorites, pinned, today])
    }

    /// The order of the spaces a sidebar lists, from a saved file: the saved order, then any
    /// space the order missed. A Blank Window's space is never listed.
    public static func spaceOrder(saved: [UUID], spaces: [Space]) -> [UUID] {
        let listed = spaces.filter { $0.standaloneWindowID == nil }
        let known = Set(listed.map(\.id))
        var order = saved.filter { known.contains($0) }
        for s in listed where !order.contains(s.id) { order.append(s.id) }
        return order
    }

    /// Blank Windows' spaces whose window is not among the saved windows (windows.json lost or
    /// reset, or a crash between the two files): they go, as the window would have taken them.
    public static func orphans(spaces: [Space], windows: [WindowSession]) -> Set<UUID> {
        Set(spaces.compactMap { s in
            guard let wid = s.standaloneWindowID else { return nil }
            return windows.contains { $0.id == wid && $0.focusedSpaceID == s.id } ? nil : s.id
        })
    }
}
