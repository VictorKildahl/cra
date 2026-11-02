import Foundation

/// Where a page an extension asks for goes: its options page, a `chrome.tabs.create`, a welcome
/// page (GitHub #107). Each Chromium profile runs its own copy of an extension, so the page
/// belongs in a space on the profile that asked: the space the window shows when that one
/// matches, else the first space on that profile. Chrome keeps one tab per options page and
/// opening it again selects that tab (#38). Arc does that across spaces too (Arc 1.171, offline,
/// 2 Nov 2026: options open in one space, asked for again from another, Arc went back to the
/// first space and selected it), but only within the profile: another profile's copy of the
/// page is another extension's, and is never reused.
public enum ExtensionPagePlacement {
    public struct Space: Equatable, Sendable {
        public let id: UUID
        /// Chromium profile folder ("Default", "Profile <id>").
        public let profile: String

        public init(id: UUID, profile: String) {
            self.id = id
            self.profile = profile
        }
    }

    public enum Target: Equatable, Sendable {
        case select(tab: UUID)
        case create(inSpace: UUID)
    }

    /// - Parameters:
    ///   - focused: the space the window shows.
    ///   - spaces: the normal (not incognito) spaces, in sidebar order.
    ///   - profile: the profile the page comes from, nil when it's the focused page's own.
    ///   - openTabs: tabs already showing the page, with their spaces; only singleton pages
    ///     (options pages) reuse one.
    public static func target(focused: Space, spaces: [Space], profile: String?,
                              openTabs: [(tab: UUID, space: UUID)], singleton: Bool) -> Target {
        let home = profile.flatMap { p in focused.profile == p ? focused : spaces.first { $0.profile == p } } ?? focused
        guard singleton else { return .create(inSpace: home.id) }
        if let open = openTabs.first(where: { $0.space == home.id }) { return .select(tab: open.tab) }
        // From an incognito space only its own tabs count: a normal one can't show there.
        if spaces.contains(home),
           let open = openTabs.first(where: { t in spaces.contains { $0.id == t.space && $0.profile == home.profile } }) {
            return .select(tab: open.tab)
        }
        return .create(inSpace: home.id)
    }
}
