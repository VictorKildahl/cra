import Foundation

// Cra's sidebar model. Shape follows what Arc persists in StorableSidebar.json
// (see docs/arc-reverse-engineering.md): spaces own a favorites, a pinned and a
// "today" container, tabs/folders are items in a tree keyed by id with explicit
// child ordering. Unlike Arc, favorites are not shared between spaces unless
// AppSettings.sharedFavorites is on (FavoritesSharing).

public typealias ItemID = UUID

public enum ContainerKind: Codable, Equatable, Hashable {
    case favorites(spaceID: UUID)
    case pinned(spaceID: UUID)
    case today(spaceID: UUID)

    public var spaceID: UUID {
        switch self {
        case .favorites(let id), .pinned(let id), .today(let id): return id
        }
    }

    /// Stands in for the space of a favorites container no one space owns: a profile's
    /// shared list (#154, `SidebarDocument.profileFavorites`), or the one every space shared
    /// in files from before favorites became per space, which SidebarStore splits up on load.
    public static let sharedFavoritesSpaceID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private enum CodingKeys: String, CodingKey { case favorites, pinned, today }
    private enum SpaceKeys: String, CodingKey { case spaceID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = c.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "No container kind"))
        }
        let s = try c.nestedContainer(keyedBy: SpaceKeys.self, forKey: key)
        switch key {
        case .favorites: self = .favorites(spaceID: try s.decodeIfPresent(UUID.self, forKey: .spaceID) ?? Self.sharedFavoritesSpaceID)
        case .pinned: self = .pinned(spaceID: try s.decode(UUID.self, forKey: .spaceID))
        case .today: self = .today(spaceID: try s.decode(UUID.self, forKey: .spaceID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let key: CodingKeys
        switch self {
        case .favorites: key = .favorites
        case .pinned: key = .pinned
        case .today: key = .today
        }
        var s = c.nestedContainer(keyedBy: SpaceKeys.self, forKey: key)
        try s.encode(spaceID, forKey: .spaceID)
    }
}

public struct TabData: Codable, Equatable {
    /// Where the tab currently is. Restored on relaunch.
    public var url: String
    /// The "home" of the tab. For pinned tabs this is what reset returns to;
    /// for today tabs it is just the URL the tab was created with.
    public var savedURL: String
    /// Last known page title.
    public var savedTitle: String
    public var muted: Bool = false
    public var timeLastActiveAt: Date?
    public var activeTabBeforeCreationID: UUID?
    /// The tab a link opened this one from (Arc: referrerID). Back with no page behind closes this
    /// tab and shows that one (BackToReferrer, #273). Saved, as the page's history is (PageHistory).
    public var referrerID: UUID?
    /// Favicon cache key: the host, then the page's own icon once it loads (FaviconKey, #211).
    public var faviconKey: String?
    /// Favicon cache key of an image the user picked; wins over the site's favicon.
    public var customIconKey: String?
    /// Favorite tile background as "#RRGGBB". nil is the theme's tile fill.
    public var tileColor: String?
    /// The live folder item this tab shows (Arc: liveItemID.url), e.g. a pull request URL.
    public var liveItemURL: String?
    /// Line under the title that the live folder writes (a pull request's author).
    public var liveSubtitle: String?
    /// When its pull request left the live folder's results; the tab goes after a grace period.
    public var liveGoneAt: Date?
    /// The page's toolbar colour as last reported (TabRuntime.themeColor). A slept or restored
    /// tab's toolbar keeps it while the page loads again, as Arc's does.
    public var themeColor: String?
    /// A pinned tab's own page title (Arc: resetTabTitle), last reported while the tab was on it.
    /// Going back to the pinned page shows it again before the page loads (GitHub #139).
    public var homeTitle: String?

    public var iconKey: String? { customIconKey ?? faviconKey }

    /// A title the page reported. On a pinned tab's own page it is also the home's name.
    public mutating func noteTitle(_ title: String, pinned: Bool) {
        savedTitle = title
        if pinned, url == savedURL, !title.isEmpty { homeTitle = title }
    }

    /// The current page becomes the home (pinning it, Replace Pinned URL with Current).
    public mutating func makeCurrentPageHome() {
        savedURL = url
        homeTitle = savedTitle.isEmpty ? nil : savedTitle
    }

    /// Back to the pinned page (Arc: resetTab): its name and favicon come back with it, not the
    /// last page's. A home whose title was never seen keeps the last one until its page reports.
    public mutating func returnHome() {
        guard url != savedURL else { return }
        url = savedURL
        if let homeTitle { savedTitle = homeTitle }
        faviconKey = FaviconKey.key(after: faviconKey, goingTo: savedURL)
    }

    public init(url: String, title: String = "") {
        self.url = url
        self.savedURL = url
        self.savedTitle = title
        self.faviconKey = URL(string: url)?.host
    }

    /// The line under the tab's title in the sidebar. Arc 1.171 (TabCellState.subtitle) has only
    /// two: the host and port of a site in developer mode (GitHub #88), else a live folder pull
    /// request's author. A pinned tab that left its page shows Arc's slash, never its host (#139).
    public func sidebarSubtitle(developerMode: Bool) -> String? {
        if developerMode, let u = URL(string: url), let host = u.host?.replacingOccurrences(of: "www.", with: "") {
            return u.port.map { "\(host):\($0)" } ?? host
        }
        if let liveSubtitle, URL(string: url)?.host == "github.com" { return liveSubtitle }
        return nil
    }
}

/// Arc's SidebarSplitViewData: a split is a sidebar item whose children are
/// the pane tabs (in pane order). Widths are stored as factors per child.
public struct SplitData: Codable, Equatable {
    public var widthFactors: [UUID: Double] = [:]
    public var orientation: SplitOrientation = .horizontal
    /// The pane that has keyboard focus (Arc: focusItemID).
    public var focusTabID: UUID?
    public var timeLastActiveAt: Date?

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        widthFactors = try c.decodeIfPresent([UUID: Double].self, forKey: .widthFactors) ?? [:]
        orientation = try c.decodeIfPresent(SplitOrientation.self, forKey: .orientation) ?? .horizontal
        focusTabID = try c.decodeIfPresent(UUID.self, forKey: .focusTabID)
        timeLastActiveAt = try c.decodeIfPresent(Date.self, forKey: .timeLastActiveAt)
    }
}

public enum SplitOrientation: String, Codable {
    /// Panes side by side (Arc's default).
    case horizontal
    /// Panes stacked top to bottom.
    case vertical
}

/// A fixed folder glyph colour, for when the theme's own doesn't read well.
public enum FolderIconStyle: String, Codable, CaseIterable {
    case white, black
}

public enum ItemData: Codable, Equatable {
    case tab(TabData)
    case folder
    case container(ContainerKind)
    case split(SplitData)
}

public struct SidebarItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var parentID: UUID?
    /// Custom title set by renaming. nil means "use the page title".
    public var title: String?
    public var children: [UUID]
    public var isUnread: Bool
    public var createdAt: Date
    public var data: ItemData
    /// A folder's glyph colour; nil is Auto (it follows the theme).
    public var folderIcon: FolderIconStyle? = nil
    /// The symbol picked with Change Icon… (Arc's folder icon picker). A key of its own, beside
    /// `folderIcon`, so a Cra that predates symbols still reads the file.
    public var folderSymbol: FolderSymbol? = nil
    /// Set on a folder that fills itself (Arc: list.automaticLiveFolderData).
    public var liveFolder: LiveFolderData? = nil
    /// A Today folder shown as a group header, as Tidy Tabs makes them (Arc: SidebarItemData.tabGroup,
    /// its title in `title`). Kept on a folder so a Cra that predates groups still reads the file.
    public var tabGroup: Bool? = nil

    public init(id: UUID, parentID: UUID?, title: String?, children: [UUID], isUnread: Bool, createdAt: Date, data: ItemData,
                folderIcon: FolderIconStyle? = nil, folderSymbol: FolderSymbol? = nil, liveFolder: LiveFolderData? = nil, tabGroup: Bool? = nil) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.children = children
        self.isUnread = isUnread
        self.createdAt = createdAt
        self.data = data
        self.folderIcon = folderIcon
        self.folderSymbol = folderSymbol
        self.liveFolder = liveFolder
        self.tabGroup = tabGroup
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentID, title, children, isUnread, createdAt, data, folderIcon, folderSymbol, liveFolder, pluginFolder, tabGroup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        children = try c.decode([UUID].self, forKey: .children)
        isUnread = try c.decode(Bool.self, forKey: .isUnread)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        data = try c.decode(ItemData.self, forKey: .data)
        folderIcon = try c.decodeIfPresent(FolderIconStyle.self, forKey: .folderIcon)
        folderSymbol = try c.decodeIfPresent(FolderSymbol.self, forKey: .folderSymbol)
        liveFolder = try c.decodeIfPresent(LiveFolderData.self, forKey: .pluginFolder)
            ?? c.decodeIfPresent(LiveFolderData.self, forKey: .liveFolder)
        tabGroup = try c.decodeIfPresent(Bool.self, forKey: .tabGroup)
    }

    /// A folder from a plugin with no GitHub or GitLab source of its own (Jira, an installed plugin)
    /// is saved under `pluginFolder`: Cra 0.1.37 and older fail the whole sidebar.json on a
    /// `liveFolder` source they don't know, and read this key's folder as a plain one with its tabs.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(children, forKey: .children)
        try c.encode(isUnread, forKey: .isUnread)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(data, forKey: .data)
        try c.encodeIfPresent(folderIcon, forKey: .folderIcon)
        try c.encodeIfPresent(folderSymbol, forKey: .folderSymbol)
        try c.encodeIfPresent(liveFolder, forKey: liveFolder?.source == .plugin ? .pluginFolder : .liveFolder)
        try c.encodeIfPresent(tabGroup, forKey: .tabGroup)
    }

    public var tab: TabData? {
        if case .tab(let t) = data { return t }
        return nil
    }
    public var isTab: Bool { tab != nil }
    public var isFolder: Bool { if case .folder = data { return true }; return false }
    public var isLiveFolder: Bool { isFolder && liveFolder != nil }
    public var isTabGroup: Bool { isFolder && tabGroup == true }
    public var split: SplitData? {
        if case .split(let s) = data { return s }
        return nil
    }
    public var isSplit: Bool { split != nil }
    /// A tab with no page yet: Arc's empty split pane ("Search or Enter URL…").
    public var isEmptyTab: Bool { tab.map { $0.url.isEmpty || $0.url == "about:blank" } ?? false }
    public var container: ContainerKind? {
        if case .container(let c) = data { return c }
        return nil
    }

    /// What the sidebar shows: the custom name wins over the page title,
    /// which wins over the host.
    public var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let tab {
            if isEmptyTab { return "New Tab" }
            if !tab.savedTitle.isEmpty { return tab.savedTitle }
            if let host = URL(string: tab.url)?.host { return host }
            return tab.url
        }
        if isSplit { return "Split View" }
        return "Untitled"
    }

    public static func split(parent: UUID?) -> SidebarItem {
        SidebarItem(id: UUID(), parentID: parent, title: nil, children: [], isUnread: false,
                    createdAt: Date(), data: .split(SplitData()))
    }

    public static func tab(_ url: String, title: String = "", parent: UUID?) -> SidebarItem {
        SidebarItem(id: UUID(), parentID: parent, title: nil, children: [], isUnread: false,
                    createdAt: Date(), data: .tab(TabData(url: url, title: title)))
    }

    public static func folder(_ name: String, parent: UUID?) -> SidebarItem {
        SidebarItem(id: UUID(), parentID: parent, title: name, children: [], isUnread: false,
                    createdAt: Date(), data: .folder)
    }

    public static func tabGroup(_ name: String, parent: UUID?) -> SidebarItem {
        SidebarItem(id: UUID(), parentID: parent, title: name, children: [], isUnread: false,
                    createdAt: Date(), data: .folder, tabGroup: true)
    }

    public static func container(_ kind: ContainerKind, id: UUID = UUID()) -> SidebarItem {
        SidebarItem(id: id, parentID: nil, title: nil, children: [], isUnread: false,
                    createdAt: Date(), data: .container(kind))
    }
}

public struct Space: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var emoji: String
    public var theme: SpaceTheme
    public var favoritesContainerID: UUID
    public var pinnedContainerID: UUID
    public var todayContainerID: UUID
    public var createdAt: Date
    /// The profile its pages load in (Arc: SpaceModel.profile); nil is the Default profile.
    public var profileID: UUID?
    /// An SF Symbol from the Icon tab of Arc's icon picker, shown instead of `emoji` (then empty).
    public var symbol: String? = nil
    /// The Blank Window this space belongs to (Arc: a `standalone` sidebar container keyed by its
    /// window). Such a space is in no window's space list and goes when its window closes (BlankWindow).
    public var standaloneWindowID: UUID? = nil
    /// GitHub #306, not in Arc (one engine per profile there): the Chromium keyword of the engine
    /// the command bar searches in this space; nil searches the profile's default.
    public var searchEngine: String? = nil

    public init(id: UUID, title: String, emoji: String, theme: SpaceTheme, favoritesContainerID: UUID, pinnedContainerID: UUID,
                todayContainerID: UUID, createdAt: Date, profileID: UUID? = nil, symbol: String? = nil, standaloneWindowID: UUID? = nil) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.theme = theme
        self.favoritesContainerID = favoritesContainerID
        self.pinnedContainerID = pinnedContainerID
        self.todayContainerID = todayContainerID
        self.createdAt = createdAt
        self.profileID = profileID
        self.symbol = symbol
        self.standaloneWindowID = standaloneWindowID
    }
}

/// Arc's Profiles: logins, cookies, site storage and Chromium's own data kept apart
/// from the Default profile. Any number of spaces can use one.
public struct BrowserProfile: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    /// Chromium's folder for it, next to Default under AppPaths.chromiumCache.
    public var directoryName: String { "Profile \(id.uuidString)" }
}

/// A profile's favorites list (Arc: StorableSidebar.topAppsContainerIDs, profile → container).
public struct ProfileFavorites: Codable, Equatable {
    /// nil is the Default profile.
    public var profileID: UUID?
    public var containerID: UUID

    public init(profileID: UUID?, containerID: UUID) {
        self.profileID = profileID
        self.containerID = containerID
    }
}

public struct SidebarDocument: Codable, Equatable {
    public var version: Int = 1
    public var spaceOrder: [UUID]
    public var spaces: [Space]
    /// The favorites container all spaces shared in older files. Only read, to
    /// split it up between the spaces; new files leave it out.
    public var favoritesContainerID: UUID?
    public var items: [SidebarItem]
    /// Profiles besides Default (missing in files from before profiles).
    public var profiles: [BrowserProfile]?
    /// Arc's favorites per profile (topApps{profile}), with AppSettings.sharedFavorites on: the
    /// list each profile's spaces show. A list outlives its spaces, as in Arc (#154).
    public var profileFavorites: [ProfileFavorites]?

    public init(version: Int = 1, spaceOrder: [UUID], spaces: [Space], favoritesContainerID: UUID? = nil, items: [SidebarItem],
                profiles: [BrowserProfile]? = nil, profileFavorites: [ProfileFavorites]? = nil) {
        self.version = version
        self.spaceOrder = spaceOrder
        self.spaces = spaces
        self.favoritesContainerID = favoritesContainerID
        self.items = items
        self.profiles = profiles
        self.profileFavorites = profileFavorites
    }

    public static func fresh() -> SidebarDocument {
        let spaceID = UUID()
        let fav = SidebarItem.container(.favorites(spaceID: spaceID))
        let pinned = SidebarItem.container(.pinned(spaceID: spaceID))
        let today = SidebarItem.container(.today(spaceID: spaceID))
        let space = Space(id: spaceID, title: "Personal", emoji: "🌱", theme: SpaceTheme.presets[0], favoritesContainerID: fav.id,
                          pinnedContainerID: pinned.id, todayContainerID: today.id, createdAt: Date())
        return SidebarDocument(spaceOrder: [spaceID], spaces: [space], items: [fav, pinned, today])
    }
}

public enum ArchiveReason: String, Codable {
    case manual, auto, clear, spaceDeleted
}

public struct ArchivedItem: Codable, Identifiable, Equatable {
    public var id: UUID { item.id }
    public var archivedAt: Date
    public var reason: ArchiveReason
    public var sourceSpaceID: UUID?
    public var wasPinned: Bool
    public var item: SidebarItem
    /// Closed from a Little Window (Arc: archive source `littleArc`); never
    /// had a place in the sidebar, so restoring puts it in the focused space.
    public var fromLittleWindow: Bool? = nil
    /// The folder it was closed out of (live folders too) and its place there:
    /// restoring puts it back while that folder is still in the space.
    public var sourceFolderID: UUID? = nil
    public var sourceIndex: Int? = nil

    public init(archivedAt: Date, reason: ArchiveReason, sourceSpaceID: UUID?, wasPinned: Bool, item: SidebarItem,
                fromLittleWindow: Bool? = nil, sourceFolderID: UUID? = nil, sourceIndex: Int? = nil) {
        self.archivedAt = archivedAt
        self.reason = reason
        self.sourceSpaceID = sourceSpaceID
        self.wasPinned = wasPinned
        self.item = item
        self.fromLittleWindow = fromLittleWindow
        self.sourceFolderID = sourceFolderID
        self.sourceIndex = sourceIndex
    }
}

/// Arc offers 12 hours to 30 days; 90 and 180 days are Cra's (#278).
public enum AutoArchiveThreshold: String, Codable, CaseIterable, Identifiable {
    case twelveHours, twentyFourHours, sevenDays, thirtyDays, ninetyDays, oneHundredEightyDays
    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self {
        case .twelveHours: return 12 * 3600
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 86400
        case .thirtyDays: return 30 * 86400
        case .ninetyDays: return 90 * 86400
        case .oneHundredEightyDays: return 180 * 86400
        }
    }
    public var label: String {
        switch self {
        case .twelveHours: return "12 hours"
        case .twentyFourHours: return "24 hours"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .ninetyDays: return "90 days"
        case .oneHundredEightyDays: return "180 days"
        }
    }

    /// Cra 0.1.36 and older know Arc's four and set the whole settings.json aside as corrupt on
    /// any other value, so a longer one is saved as 30 days with `AppSettings.autoArchiveDays`
    /// beside it, which they ignore. A value from a newer Cra loads as the longest one this Cra
    /// knows: a threshold only ever archives later than asked, never sooner.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.allCases.last!
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(longerThanArc ? Self.thirtyDays.rawValue : rawValue)
    }

    var longerThanArc: Bool { seconds > Self.thirtyDays.seconds }
    var days: Int { Int(seconds / 86400) }

    /// The shortest threshold that archives no sooner than `days`.
    init(days: Int) {
        self = Self.allCases.first { $0.seconds >= TimeInterval(days) * 86400 } ?? Self.allCases.last!
    }
}

public enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, duckduckgo, bing, kagi
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .kagi: return "Kagi"
        }
    }
    public func searchURL(_ query: String) -> String {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26") ?? query
        switch self {
        case .google: return "https://www.google.com/search?q=\(q)"
        case .duckduckgo: return "https://duckduckgo.com/?q=\(q)"
        case .bing: return "https://www.bing.com/search?q=\(q)"
        case .kagi: return "https://kagi.com/search?q=\(q)"
        }
    }
    /// Each engine's OpenSearch suggest endpoint, for the command bar's search suggestions.
    public func suggestURL(_ query: String) -> URL? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        switch self {
        case .google: return URL(string: "https://www.google.com/complete/search?client=chrome&ie=utf-8&oe=utf-8&q=\(q)")
        case .duckduckgo: return URL(string: "https://duckduckgo.com/ac/?type=list&q=\(q)")
        case .bing: return URL(string: "https://api.bing.com/osjson.aspx?query=\(q)")
        case .kagi: return URL(string: "https://kagi.com/api/autosuggest?q=\(q)")
        }
    }
}

public struct AppSettings: Codable, Equatable {
    public var autoArchive: AutoArchiveThreshold = .twelveHours {
        didSet { autoArchiveDays = autoArchive.longerThanArc ? autoArchive.days : nil }
    }
    /// 90 or 180 when `autoArchive` is longer than Arc's 30 days, which settings.json then holds.
    public private(set) var autoArchiveDays: Int?
    public var searchEngine: SearchEngine = .google
    public var newTabsAtTop: Bool = true
    /// Tabs ▸ "Show the New Tab button above tabs": the + New Tab row leads Today
    /// instead of following its last tab. On like Arc, which keeps it under the divider.
    public var newTabButtonAtTop: Bool = true
    /// Cra 0.1.15–0.1.23 saved the New Tab row below Today for everyone; settings without
    /// this mark move it back above, where Arc has it, once.
    public var newTabButtonDefaultMigrated: Bool = true
    public var showStatusBar: Bool = true
    /// Arc's toolbar above the page (URL, copy link, DevTools). ⇧⌘D toggles. Off by
    /// default like Arc, which keeps the URL at the top of the sidebar.
    public var showToolbar: Bool = false
    /// Cra 0.1.0 saved `showToolbar` as on for everyone; settings without this mark
    /// take the toolbar from Arc's own preference once (off without Arc).
    public var toolbarDefaultMigrated: Bool = true
    /// Arc's "Show Full URL" on the toolbar address's menu (toolbarShowFullURLsEnabledPreference):
    /// the normal bar shows the host and the dimmer path. Off like Arc, which shows the host only.
    public var toolbarShowsFullURL: Bool = false
    public var hasSeenImportPrompt: Bool = false
    /// Arc's per-site Developer Mode (⌃D): the toolbar shows the full URL in
    /// monospace with the developer icons, and the nav buttons move to the sidebar.
    public var developerHosts: Set<String> = []
    /// Arc's `disabledDefaultHosts`: local servers start in Developer Mode, and ⌃D on one
    /// records its host here (#228).
    public var disabledDefaultDeveloperHosts: Set<String> = []
    /// Host pages in Chrome-style windows: Chrome extensions and Chrome's own
    /// DevTools docking. Needs a restart to change.
    public var chromeEngine: Bool = true
    /// Air Traffic Control's "Default": where links from other apps open when no route
    /// matches. Arc's "Links from other apps open in Little Arc" switch is this set to
    /// Little Arc (on) or the most recent space (off).
    public var defaultLinkDestination: LinkDestination = .littleWindowInUse
    /// Air Traffic Control routes, checked in order (LinkRouting.swift). Starts with Arc's
    /// Google Meet route.
    public var linkRoutes: [LinkRoute] = [.googleMeet]
    /// Arc's "Open a Peek window when clicking on links to other sites" (modalEnabled): only
    /// links clicked in favorites and pinned tabs.
    public var peekLinksToOtherSites: Bool = true
    /// Cra's addition (issue #12): links to other sites peek from every tab, not only
    /// favorites and pinned tabs.
    public var peekInEveryTab: Bool = false
    /// Cra's addition (GitHub #380), off by default: ⌘-clicking a Peek's Expand button loads the page
    /// in the tab the Peek came from instead of a new tab (PeekExpand). Arc's Expand always made a tab.
    public var peekExpandInSourceTab: Bool = false
    /// Arc's "Open a Peek window when clicking on links with Shift held"
    /// (shiftClickModalEntryPointEnabled).
    public var peekOnShiftClick: Bool = true
    /// Arc's "Open Little Arc when I press ⌥⌘N" (globalLittleBrowserHotkeyEnabled, on by default):
    /// New Little Window's shortcut works from every app, full-screen ones too (GitHub #195).
    public var littleWindowShortcutEverywhere: Bool = true
    /// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (optionCommandClickLittleArcEntryPointEnabled,
    /// on in the Arc 1.172.2 measured on 11 Nov 2026): a link clicked with both keys down opens in a Little Window
    /// (LittleWindowTrigger). Off in Cra, unlike Arc: since 0.1.38 a ⌘⌥-click opens Split View (#298,
    /// Chromium 156's own split view click), and this switch takes that click over.
    public var littleWindowOnOptionCommandClick: Bool = false
    /// A page's "Open Link in New Tab" switches to the tab it opens (LinkMenu). Off as in Arc, whose
    /// item leaves the page in front and the tab loading behind it (GitHub #276). A new key: #183's
    /// openLinksInBackground was off (switch) in every settings.json that never turned it on.
    public var openLinksInForeground: Bool = false
    /// Arc's Previews ▸ Folders (folderPreviewEnabled): resting the pointer on a closed folder
    /// lists its tabs, most recent first, with a search field.
    public var folderPreviews: Bool = true
    /// Arc: "Enable Picture in Picture when you leave a video tab". The default for every site
    /// without a choice of its own in `autoPictureInPictureSites`.
    public var autoPictureInPicture: Bool = true
    /// The Site Control Center's Automatic Picture-In-Picture switch, per site like Arc's (#326):
    /// a site's own choice, which outlasts a change to `autoPictureInPicture`.
    public var autoPictureInPictureSites: [String: Bool] = [:]
    /// Dia's onboarding privacy choice "Block third-party ads and trackers": requests
    /// to listed ad and tracker domains are cancelled unless they are first-party.
    public var blockAdsAndTrackers: Bool = true
    /// Dia's Tabs ▸ "Haptic feedback when reordering tabs" (tabReorderingHapticsEnabled).
    public var hapticFeedbackOnReorder: Bool = true
    /// Dia's Advanced ▸ "Warn before quitting" (shouldWarnBeforeQuitting, off by default).
    public var warnBeforeQuitting: Bool = false
    /// GitHub #231, not in Arc (Arc quits on ⌘Q): ⌘Q puts the pages away and Cra stays in the menu
    /// bar, so ⌥⌘N opens a Little Window without a launch. Off, ⌘Q quits as in Arc (MenuBarMode).
    public var keepInMenuBar: Bool = false
    /// Dia's Tabs ▸ "Clean up tabs I haven't used in:" checkbox; `autoArchive` keeps the
    /// threshold while this is off.
    public var autoArchiveEnabled: Bool = true
    /// Tabs ▸ "Force tabs out of memory after:" (GitHub #153): on at Arc's 4 hours, like 0.1.28,
    /// which had no setting. Off, the clock closes no page. Keys of their own: the switch 0.1.22–0.1.27
    /// saved (tabSleepEnabled, tabSleep) must not turn this off on update.
    public var tabSleepTimerEnabled: Bool = true
    public var tabSleepAfter: TabSleepThreshold = .fourHours
    /// Tabs ▸ "Force tabs out of memory when the Mac is short of memory" (GitHub #153), off like Arc.
    public var tabSleepOnMemoryPressure: Bool = false
    /// Privacy ▸ "Always use secure connections": Chrome's HTTPS-Only Mode.
    public var httpsOnly: Bool = false
    /// Privacy ▸ "Fingerprinting protection" (not in Arc, off by default): Cra's Chromium adds
    /// faint noise to what pages read back from canvas, WebGL and offline audio, and reports 8
    /// processor cores, with a seed per site, profile and launch (fingerprinting-protection.patch).
    public var fingerprintingProtection: Bool = false
    /// Arc's View ▸ Appearance: what websites see as the colour scheme.
    public var websiteAppearance: WebsiteAppearance = .automatic
    /// Arc's Settings ▸ Advanced "Play Arc sound effects" (the capture shutter), on by default.
    public var soundEffects: Bool = true
    /// Arc's Library ▸ Media: off until "Show Media" is pressed (reading Desktop and Documents
    /// asks macOS for access), then the folders the Library button's "Show media" menu ticks.
    public var mediaLibraryEnabled: Bool = false
    public var mediaFolders: [MediaLibrary.Folder] = MediaLibrary.Folder.allCases
    /// Files taken off Library ▸ Media with Arc's "Hide from Arc" (the file stays on disk).
    public var mediaHidden: [String] = []
    /// Arc's Settings ▸ Links ▸ "Archive Little Arcs after:".
    public var littleWindowArchiveAfter: LittleWindowArchive = .sixHours
    /// Arc's Settings ▸ Advanced "When opening Arc, restore windows from previous session", on by default.
    public var restoreWindows: Bool = true
    /// Settings ▸ Advanced "When opening Cra, start on a new tab" (X DM 7 Nov 2026, not in Arc): off,
    /// Cra opens on the tab in use last, as Arc does (LaunchStart).
    public var startOnNewTab: Bool = false
    /// Arc's Settings ▸ Advanced "Allow websites to get your theme data" (ArcThemeData), on by default.
    public var shareThemeWithWebsites: Bool = true
    /// Arc's Settings ▸ General "Block Cookie Banners" (CookieBanners), off by default as in Arc.
    public var blockCookieBanners: Bool = false
    /// Arc's View ▸ Developer ▸ "Allow JavaScript from Apple Events": AppleScript's `execute`, off by default.
    public var allowAppleEventsJavaScript: Bool = false
    /// Arc's Settings ▸ Advanced "Allow window dragging from the top of webpages" (PageTopDrag), on by default.
    public var pageTopWindowDrag: Bool = true
    /// Arc's Settings ▸ Advanced "Enable Boosts on websites you visit", on by default.
    public var boostsEnabled: Bool = true
    /// Arc's Settings ▸ General ▸ Previews: hovering a Gmail favorite shows its unread mail.
    public var favoritePreviews: Bool = true
    /// Previews Settings… ▸ "Recent pages on Linear, Notion, and Figma" (GitHub #376): hovering a
    /// favorite or pinned tab on Linear, Notion, Figma or Confluence lists the pages you visited there.
    public var recentPagesPreviews: Bool = true
    /// Cra's addition (PR #267, Dia-like): the open favorite's rim takes its logo's colours.
    /// Off keeps Arc's neutral 2 pt rim.
    public var favoriteLogoOutline: Bool = false
    /// Arc's Live Calendar on a Google Calendar favorite (the favorite's menu ▸ Live Calendar), on
    /// until "Disable Live Calendar".
    public var liveCalendar: Bool = true
    /// Live Calendar ▸ Show Hover Preview: today's timeline when the pointer rests on the tile.
    public var calendarHoverPreview: Bool = true
    /// Live Calendar ▸ Show Time to Next Meeting: the tile counts down to it.
    public var calendarTimeToNextMeeting: Bool = true
    /// Live Calendar ▸ Show Next Meeting Link, Two Minutes Before in Arc.
    public var calendarMeetingLink: CalendarPreview.LinkTiming = .twoMinutes
    /// Arc's searchSuggestEnabled: the command bar asks the search engine for suggestions
    /// as you type and fills its rows with them.
    public var searchSuggestions: Bool = true
    /// GitHub #307, not in Arc: ⌘T searches and lists only the open tabs of the window's space
    /// (`TabSearchScope.commandBarTabs`). Off is Arc's bar, which finds a tab in any space.
    public var commandBarCurrentSpaceOnly: Bool = false
    /// GitHub #344, not in Arc: a click on the sidebar's URL field edits the address where it is
    /// (`SidebarAddressEdit`). Off is Arc's, which opens the command bar; ⌘L opens it either way.
    public var editAddressInPlace: Bool = false
    /// Arc's showSpaceHeaderOnSingleUnnamedSpaces: with only one space, its header (and the
    /// dock's lone space icon) can be hidden, for people who don't use spaces.
    public var showSpaceHeaderOnSingleSpace: Bool = true
    /// GitHub #154: the spaces of one profile show one set of favorites, as Arc's do (a topApps
    /// container per profile). Off by default: Cra keeps favorites per space (FavoritesSharing).
    public var sharedFavorites: Bool = false
    /// GitHub #24, not in Arc: the page fills the window with no margin and no rounded
    /// card, like a traditional browser. Off by default.
    public var edgeToEdgeContent: Bool = false
    /// GitHub #91, Settings ▸ Performance: Cra records its own performance on this Mac (stalls,
    /// CPU and memory per process, tab timings) for Help ▸ Export Diagnostics. On by default in
    /// early releases; nothing leaves the Mac. Changing the default needs no migration.
    public var perfRecording: Bool = AppSettings.perfRecordingDefault
    public static let perfRecordingDefault = true
    /// Settings ▸ Performance ▸ "Hide site names": every site in the diagnostics zip becomes site-N.
    public var perfHidesSiteNames: Bool = false
    /// Arc Max's Tidy Tabs (tidyTabsEnabled), done by the Mac's Apple Intelligence model: the Today
    /// divider's Tidy button. On by default; the button only shows while Apple Intelligence is on.
    public var tidyTabs: Bool = true
    /// Arc Max's Tidy Tab Titles (renamePinnedTabsEnabled): a tab you pin gets a shorter name from the
    /// Mac's Apple Intelligence model. Off by default: it renames, where Tidy waits for a click.
    public var tidyTabTitles: Bool = false
    /// Arc Max's Tidy Downloads (renameDownloadsEnabled): a finished download gets a readable name from
    /// the Mac's Apple Intelligence model. Off by default, like Arc Max.
    public var tidyDownloads: Bool = false
    /// Arc Max's 5-Second Previews (fiveSecondPreviewsEnabled / fiveSecondPreviews): hover or Shift-hover
    /// on a link generates a summary of the webpage using the Mac's Apple Intelligence model.
    /// Off by default, like Arc Max.
    public var fiveSecondPreviews: Bool = false
    /// Arc's per-profile Download location (#190), by DownloadLocation.key(profileID:). A profile
    /// that isn't here saves to the Downloads folder without asking.
    public var downloadLocations: [String: DownloadLocation] = [:]
    /// Arc's per-profile "New documents" (#375), by NewDocumentApp.key(profileID:): the app the
    /// command bar's "New …" command opens. A profile that isn't here has none (Arc's "——").
    public var newDocumentApps: [String: NewDocumentApp] = [:]
    /// Settings ▸ Privacy ▸ "Share anonymous usage stats" and onboarding's Privacy step (Dia's
    /// "Help improve Dia" row): a daily UsageStats report. Off unless the user turns it on.
    public var shareUsageStats: Bool = false
    /// Settings ▸ Privacy ▸ Crash reports: after a crash Cra asks before sending the report
    /// (CrashReports.reduce), sends it without asking, or never.
    public var crashReports: CrashReportChoice = .ask
    /// The sidebar's "Help improve Cra" card was answered (Share, its ✕) or onboarding's Privacy
    /// step was passed: the card doesn't come back (SharingPrompt).
    public var askedToShare: Bool = false

    public func downloadLocation(profileID: UUID?) -> DownloadLocation {
        downloadLocations[DownloadLocation.key(profileID: profileID)] ?? DownloadLocation()
    }

    public mutating func setDownloadLocation(_ location: DownloadLocation, profileID: UUID?) {
        downloadLocations[DownloadLocation.key(profileID: profileID)] = location == DownloadLocation() ? nil : location
    }

    public init() {}

    public static func siteKey(for url: String) -> String? {
        URL(string: url)?.host?.lowercased().replacingOccurrences(of: "www.", with: "")
    }
    /// Arc's "Links from other apps open in Little Arc" (URLs handed over by other apps
    /// open in a small disposable window instead of a sidebar tab).
    public var openExternalLinksInLittleWindow: Bool {
        get { defaultLinkDestination.isLittleWindow }
        set {
            guard newValue != openExternalLinksInLittleWindow else { return }
            defaultLinkDestination = newValue ? .littleWindowInUse : .mostRecentSpace
        }
    }
    /// Hosts Arc puts in Developer Mode by itself, on any port: localhost, 127.0.0.1 and any
    /// *.localhost, not [::1] (Arc 1.172, checked live 8 Nov 2026).
    public static func isDefaultDeveloperHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".localhost")
    }
    public func isDeveloperMode(url: String) -> Bool {
        guard let k = AppSettings.siteKey(for: url) else { return false }
        return developerHosts.contains(k)
            || (Self.isDefaultDeveloperHost(k) && !disabledDefaultDeveloperHosts.contains(k))
    }
    /// Whether a page shown alone carries a bar above it: the toolbar while it is shown, and
    /// Arc's developer bar on a Developer Mode site even with the toolbar hidden (#185). A
    /// split's panes always carry bars (#178); the shell adds that rule.
    public func showsBar(above url: String?) -> Bool {
        showToolbar || url.map(isDeveloperMode) == true
    }
    public mutating func toggleDeveloperMode(url: String) {
        guard let k = AppSettings.siteKey(for: url) else { return }
        let on = isDeveloperMode(url: url)
        if Self.isDefaultDeveloperHost(k) {
            developerHosts.remove(k)
            if on { disabledDefaultDeveloperHosts.insert(k) } else { disabledDefaultDeveloperHosts.remove(k) }
        } else if on { developerHosts.remove(k) } else { developerHosts.insert(k) }
    }
    /// Whether leaving a video tab on this page's site opens Picture in Picture.
    public func allowsAutoPictureInPicture(url: String) -> Bool {
        AppSettings.siteKey(for: url).flatMap { autoPictureInPictureSites[$0] } ?? autoPictureInPicture
    }
    /// The Site Control Center's switch: flips this site only. A site switched back to the setting
    /// for every site follows that setting again.
    public mutating func toggleAutoPictureInPicture(url: String) {
        guard let k = AppSettings.siteKey(for: url) else { return }
        let on = !allowsAutoPictureInPicture(url: url)
        autoPictureInPictureSites[k] = on == autoPictureInPicture ? nil : on
    }
    /// Settings saved without `toolbarDefaultMigrated` take the toolbar from Arc's View ▸
    /// Show Toolbar (nil without Arc: off), once. Arc's preference is read only then.
    public mutating func migrateToolbarDefault(arcShowsToolbar: @autoclosure () -> Bool?) {
        guard !toolbarDefaultMigrated else { return }
        showToolbar = arcShowsToolbar() ?? false
        toolbarDefaultMigrated = true
    }
}

/// One browser window. Each window shows its own space and remembers its own
/// open tab per space; spaces and tabs themselves are shared (Arc).
public struct WindowSession: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var focusedSpaceID: UUID?
    public var selectedTabPerSpace: [UUID: UUID] = [:]
    public var frame: String?
    public var sidebarVisible = true
    /// Incognito windows show a space of their own, never saved (SidebarStore.addIncognitoWindow).
    public var isIncognito = false

    public init(id: UUID = UUID(), focusedSpaceID: UUID? = nil, selectedTabPerSpace: [UUID: UUID] = [:], frame: String? = nil,
                sidebarVisible: Bool = true, isIncognito: Bool = false) {
        self.id = id
        self.focusedSpaceID = focusedSpaceID
        self.selectedTabPerSpace = selectedTabPerSpace
        self.frame = frame
        self.sidebarVisible = sidebarVisible
        self.isIncognito = isIncognito
    }
}

public struct WindowPrefs: Codable, Equatable {
    public var sidebarWidth: Double = 328
    public var expandedFolders: Set<UUID> = []
    public var collapsedPinnedSpaces: Set<UUID> = []
    /// Arc's topAppsEmptyStateDismissedForProfiles: favorites containers whose empty-state card
    /// ("Drag to add Favorites") was closed with its ×. It stays closed.
    public var favoritesEmptyStateDismissed: Set<UUID> = []
    /// Arc's commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed: Dismiss on the command bar's
    /// "We talk to your search engine…" banner. The (i) that opens it stays gone (SearchSuggestionsNotice).
    public var searchSuggestionsNoticeDismissed: Bool = false
    /// Closed folders that keep tabs in sight (FolderPeek): folder → its peeked tabs.
    public var peekedFolders: [UUID: [UUID]] = [:]
    /// Open browser windows, restored at launch. Never empty.
    public var windows: [WindowSession] = [WindowSession()]

    /// What is written to windows.json: incognito windows are never restored.
    public var withoutIncognito: WindowPrefs {
        var p = self
        p.windows.removeAll { $0.isIncognito }
        return p
    }
    /// Last Little Window size (Arc: LittleBrowserWindow_size).
    public var littleWindowSize: String?

    public init(sidebarWidth: Double = 328, expandedFolders: Set<UUID> = [], collapsedPinnedSpaces: Set<UUID> = [],
                favoritesEmptyStateDismissed: Set<UUID> = [], peekedFolders: [UUID: [UUID]] = [:],
                windows: [WindowSession] = [WindowSession()], littleWindowSize: String? = nil) {
        self.sidebarWidth = sidebarWidth
        self.expandedFolders = expandedFolders
        self.collapsedPinnedSpaces = collapsedPinnedSpaces
        self.favoritesEmptyStateDismissed = favoritesEmptyStateDismissed
        self.peekedFolders = peekedFolders
        self.windows = windows
        self.littleWindowSize = littleWindowSize
    }
}

public struct HistoryEntry: Codable, Equatable {
    public var url: String
    public var title: String
    public var lastVisit: Date
    public var visitCount: Int

    public init(url: String, title: String, lastVisit: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
}

/// Signals the command bar learns from, mirroring Arc's
/// StorableCommandBarAdditionalRanking.json (recentlySwitchedToTabs,
/// queriesToSelectedArchetype, typeTravelUsage).
public struct RankingData: Codable, Equatable {
    public var recentlySwitchedToTabs: [UUID: [Date]] = [:]
    public var queriesToSelected: [String: String] = [:]
    public var commandUsage: [String: Int] = [:]

    public init(recentlySwitchedToTabs: [UUID: [Date]] = [:], queriesToSelected: [String: String] = [:], commandUsage: [String: Int] = [:]) {
        self.recentlySwitchedToTabs = recentlySwitchedToTabs
        self.queriesToSelected = queriesToSelected
        self.commandUsage = commandUsage
    }
}


// Tolerant decoding so new preference keys never reset the file.
extension AppSettings {
    /// Keys earlier versions wrote; read once and replaced.
    private enum LegacyKeys: String, CodingKey { case openExternalLinksInLittleWindow }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let days = try? c.decodeIfPresent(Int.self, forKey: .autoArchiveDays) {
            autoArchive = AutoArchiveThreshold(days: days)
        } else {
            autoArchive = (try? c.decodeIfPresent(AutoArchiveThreshold.self, forKey: .autoArchive)) ?? .twelveHours
        }
        // An initializer doesn't run didSet.
        autoArchiveDays = autoArchive.longerThanArc ? autoArchive.days : nil
        searchEngine = (try? c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine)) ?? .google
        newTabsAtTop = try c.decodeIfPresent(Bool.self, forKey: .newTabsAtTop) ?? true
        if try c.decodeIfPresent(Bool.self, forKey: .newTabButtonDefaultMigrated) == true {
            newTabButtonAtTop = try c.decodeIfPresent(Bool.self, forKey: .newTabButtonAtTop) ?? true
        }
        showStatusBar = try c.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? true
        // Without the mark, `showToolbar` waits for migrateToolbarDefault(arcShowsToolbar:).
        toolbarDefaultMigrated = try c.decodeIfPresent(Bool.self, forKey: .toolbarDefaultMigrated) == true
        if toolbarDefaultMigrated {
            showToolbar = try c.decodeIfPresent(Bool.self, forKey: .showToolbar) ?? false
        }
        toolbarShowsFullURL = try c.decodeIfPresent(Bool.self, forKey: .toolbarShowsFullURL) ?? false
        hasSeenImportPrompt = try c.decodeIfPresent(Bool.self, forKey: .hasSeenImportPrompt) ?? false
        developerHosts = try c.decodeIfPresent(Set<String>.self, forKey: .developerHosts) ?? []
        disabledDefaultDeveloperHosts = try c.decodeIfPresent(Set<String>.self, forKey: .disabledDefaultDeveloperHosts) ?? []
        chromeEngine = try c.decodeIfPresent(Bool.self, forKey: .chromeEngine) ?? true
        autoPictureInPicture = try c.decodeIfPresent(Bool.self, forKey: .autoPictureInPicture) ?? true
        autoPictureInPictureSites = (try? c.decodeIfPresent([String: Bool].self, forKey: .autoPictureInPictureSites)) ?? [:]
        blockAdsAndTrackers = try c.decodeIfPresent(Bool.self, forKey: .blockAdsAndTrackers) ?? true
        if let d = try? c.decodeIfPresent(LinkDestination.self, forKey: .defaultLinkDestination) {
            defaultLinkDestination = d
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            openExternalLinksInLittleWindow = try legacy.decodeIfPresent(Bool.self, forKey: .openExternalLinksInLittleWindow) ?? true
        }
        // Settings from before Air Traffic Control get Arc's Google Meet route once.
        linkRoutes = c.contains(.linkRoutes) ? (try? c.decode([LinkRoute].self, forKey: .linkRoutes)) ?? [] : [.googleMeet]
        peekLinksToOtherSites = try c.decodeIfPresent(Bool.self, forKey: .peekLinksToOtherSites) ?? true
        peekInEveryTab = try c.decodeIfPresent(Bool.self, forKey: .peekInEveryTab) ?? false
        peekExpandInSourceTab = try c.decodeIfPresent(Bool.self, forKey: .peekExpandInSourceTab) ?? false
        peekOnShiftClick = try c.decodeIfPresent(Bool.self, forKey: .peekOnShiftClick) ?? true
        littleWindowShortcutEverywhere = try c.decodeIfPresent(Bool.self, forKey: .littleWindowShortcutEverywhere) ?? true
        littleWindowOnOptionCommandClick = try c.decodeIfPresent(Bool.self, forKey: .littleWindowOnOptionCommandClick) ?? false
        openLinksInForeground = try c.decodeIfPresent(Bool.self, forKey: .openLinksInForeground) ?? false
        folderPreviews = try c.decodeIfPresent(Bool.self, forKey: .folderPreviews) ?? true
        hapticFeedbackOnReorder = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedbackOnReorder) ?? true
        warnBeforeQuitting = try c.decodeIfPresent(Bool.self, forKey: .warnBeforeQuitting) ?? false
        keepInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .keepInMenuBar) ?? false
        autoArchiveEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoArchiveEnabled) ?? true
        tabSleepTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabSleepTimerEnabled) ?? true
        tabSleepAfter = (try? c.decodeIfPresent(TabSleepThreshold.self, forKey: .tabSleepAfter)) ?? .fourHours
        tabSleepOnMemoryPressure = try c.decodeIfPresent(Bool.self, forKey: .tabSleepOnMemoryPressure) ?? false
        httpsOnly = try c.decodeIfPresent(Bool.self, forKey: .httpsOnly) ?? false
        fingerprintingProtection = try c.decodeIfPresent(Bool.self, forKey: .fingerprintingProtection) ?? false
        websiteAppearance = (try? c.decodeIfPresent(WebsiteAppearance.self, forKey: .websiteAppearance)) ?? .automatic
        soundEffects = try c.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? true
        mediaLibraryEnabled = try c.decodeIfPresent(Bool.self, forKey: .mediaLibraryEnabled) ?? false
        mediaFolders = (try? c.decodeIfPresent([MediaLibrary.Folder].self, forKey: .mediaFolders)) ?? MediaLibrary.Folder.allCases
        mediaHidden = (try? c.decodeIfPresent([String].self, forKey: .mediaHidden)) ?? []
        littleWindowArchiveAfter = (try? c.decodeIfPresent(LittleWindowArchive.self, forKey: .littleWindowArchiveAfter)) ?? .sixHours
        restoreWindows = try c.decodeIfPresent(Bool.self, forKey: .restoreWindows) ?? true
        startOnNewTab = try c.decodeIfPresent(Bool.self, forKey: .startOnNewTab) ?? false
        shareThemeWithWebsites = try c.decodeIfPresent(Bool.self, forKey: .shareThemeWithWebsites) ?? true
        blockCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .blockCookieBanners) ?? false
        allowAppleEventsJavaScript = try c.decodeIfPresent(Bool.self, forKey: .allowAppleEventsJavaScript) ?? false
        pageTopWindowDrag = try c.decodeIfPresent(Bool.self, forKey: .pageTopWindowDrag) ?? true
        boostsEnabled = try c.decodeIfPresent(Bool.self, forKey: .boostsEnabled) ?? true
        favoritePreviews = try c.decodeIfPresent(Bool.self, forKey: .favoritePreviews) ?? true
        recentPagesPreviews = try c.decodeIfPresent(Bool.self, forKey: .recentPagesPreviews) ?? true
        favoriteLogoOutline = try c.decodeIfPresent(Bool.self, forKey: .favoriteLogoOutline) ?? false
        liveCalendar = try c.decodeIfPresent(Bool.self, forKey: .liveCalendar) ?? true
        calendarHoverPreview = try c.decodeIfPresent(Bool.self, forKey: .calendarHoverPreview) ?? true
        calendarTimeToNextMeeting = try c.decodeIfPresent(Bool.self, forKey: .calendarTimeToNextMeeting) ?? true
        calendarMeetingLink = (try? c.decodeIfPresent(CalendarPreview.LinkTiming.self, forKey: .calendarMeetingLink)) ?? .twoMinutes
        searchSuggestions = try c.decodeIfPresent(Bool.self, forKey: .searchSuggestions) ?? true
        commandBarCurrentSpaceOnly = try c.decodeIfPresent(Bool.self, forKey: .commandBarCurrentSpaceOnly) ?? false
        editAddressInPlace = try c.decodeIfPresent(Bool.self, forKey: .editAddressInPlace) ?? false
        showSpaceHeaderOnSingleSpace = try c.decodeIfPresent(Bool.self, forKey: .showSpaceHeaderOnSingleSpace) ?? true
        sharedFavorites = try c.decodeIfPresent(Bool.self, forKey: .sharedFavorites) ?? false
        edgeToEdgeContent = try c.decodeIfPresent(Bool.self, forKey: .edgeToEdgeContent) ?? false
        perfRecording = try c.decodeIfPresent(Bool.self, forKey: .perfRecording) ?? Self.perfRecordingDefault
        perfHidesSiteNames = try c.decodeIfPresent(Bool.self, forKey: .perfHidesSiteNames) ?? false
        tidyTabs = try c.decodeIfPresent(Bool.self, forKey: .tidyTabs) ?? true
        tidyTabTitles = try c.decodeIfPresent(Bool.self, forKey: .tidyTabTitles) ?? false
        tidyDownloads = try c.decodeIfPresent(Bool.self, forKey: .tidyDownloads) ?? false
        fiveSecondPreviews = try c.decodeIfPresent(Bool.self, forKey: .fiveSecondPreviews) ?? false
        downloadLocations = (try? c.decodeIfPresent([String: DownloadLocation].self, forKey: .downloadLocations)) ?? [:]
        newDocumentApps = NewDocumentApp.decodeMap(try? c.decodeIfPresent([String: String].self, forKey: .newDocumentApps))
        shareUsageStats = try c.decodeIfPresent(Bool.self, forKey: .shareUsageStats) ?? false
        crashReports = (try? c.decodeIfPresent(CrashReportChoice.self, forKey: .crashReports)) ?? .ask
        askedToShare = try c.decodeIfPresent(Bool.self, forKey: .askedToShare) ?? false
    }
}

extension WindowPrefs {
    /// Single-window builds kept the window's state at the top level.
    private enum LegacyKeys: String, CodingKey { case sidebarVisible, focusedSpaceID, selectedTabPerSpace, windowFrame }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 328
        expandedFolders = try c.decodeIfPresent(Set<UUID>.self, forKey: .expandedFolders) ?? []
        collapsedPinnedSpaces = try c.decodeIfPresent(Set<UUID>.self, forKey: .collapsedPinnedSpaces) ?? []
        favoritesEmptyStateDismissed = try c.decodeIfPresent(Set<UUID>.self, forKey: .favoritesEmptyStateDismissed) ?? []
        searchSuggestionsNoticeDismissed = try c.decodeIfPresent(Bool.self, forKey: .searchSuggestionsNoticeDismissed) ?? false
        peekedFolders = (try? c.decodeIfPresent([UUID: [UUID]].self, forKey: .peekedFolders)) ?? [:]
        if let saved = try? c.decodeIfPresent([WindowSession].self, forKey: .windows), !saved.isEmpty {
            windows = saved
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            windows = [WindowSession(focusedSpaceID: try legacy.decodeIfPresent(UUID.self, forKey: .focusedSpaceID),
                                     selectedTabPerSpace: try legacy.decodeIfPresent([UUID: UUID].self, forKey: .selectedTabPerSpace) ?? [:],
                                     frame: try legacy.decodeIfPresent(String.self, forKey: .windowFrame),
                                     sidebarVisible: try legacy.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true)]
        }
        littleWindowSize = try c.decodeIfPresent(String.self, forKey: .littleWindowSize)
    }
}

extension WindowSession {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        focusedSpaceID = try c.decodeIfPresent(UUID.self, forKey: .focusedSpaceID)
        selectedTabPerSpace = try c.decodeIfPresent([UUID: UUID].self, forKey: .selectedTabPerSpace) ?? [:]
        frame = try c.decodeIfPresent(String.self, forKey: .frame)
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
    }
}

extension Space {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        emoji = try c.decode(String.self, forKey: .emoji)
        theme = try c.decode(SpaceTheme.self, forKey: .theme)
        // Spaces saved while favorites were shared get a container on load (SidebarStore.repair).
        favoritesContainerID = try c.decodeIfPresent(UUID.self, forKey: .favoritesContainerID) ?? UUID()
        pinnedContainerID = try c.decode(UUID.self, forKey: .pinnedContainerID)
        todayContainerID = try c.decode(UUID.self, forKey: .todayContainerID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        standaloneWindowID = try c.decodeIfPresent(UUID.self, forKey: .standaloneWindowID)
        searchEngine = try c.decodeIfPresent(String.self, forKey: .searchEngine)
        // Edit Space… → Save in 0.1.31 and older wrote 🌱 beside a space's symbol, and the sidebar
        // drew both stacked (#205). The symbol was the space's icon, so the emoji beside it goes.
        if symbol?.isEmpty == false { emoji = "" }
    }
}

extension TabData {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        savedURL = try c.decodeIfPresent(String.self, forKey: .savedURL) ?? url
        savedTitle = try c.decodeIfPresent(String.self, forKey: .savedTitle) ?? ""
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        timeLastActiveAt = try c.decodeIfPresent(Date.self, forKey: .timeLastActiveAt)
        activeTabBeforeCreationID = try c.decodeIfPresent(UUID.self, forKey: .activeTabBeforeCreationID)
        referrerID = try c.decodeIfPresent(UUID.self, forKey: .referrerID)
        faviconKey = try c.decodeIfPresent(String.self, forKey: .faviconKey) ?? URL(string: url)?.host
        customIconKey = try c.decodeIfPresent(String.self, forKey: .customIconKey)
        tileColor = try c.decodeIfPresent(String.self, forKey: .tileColor)
        liveItemURL = try c.decodeIfPresent(String.self, forKey: .liveItemURL)
        liveSubtitle = try c.decodeIfPresent(String.self, forKey: .liveSubtitle)
        liveGoneAt = try c.decodeIfPresent(Date.self, forKey: .liveGoneAt)
        themeColor = try c.decodeIfPresent(String.self, forKey: .themeColor)
        homeTitle = try c.decodeIfPresent(String.self, forKey: .homeTitle)
    }
}

/// Arc's View ▸ Appearance ("Websites, Easels, and Notes will use:", in the command bar "Switch to
/// Light Mode" and the like): Automatic follows the Mac. Light and Dark turn the browser as well as
/// its pages, as Arc's do: its windows, menus, command bar and Auto space themes (#362).
public enum WebsiteAppearance: String, Codable, CaseIterable, Sendable {
    case automatic, light, dark

    /// The appearance the browser itself takes: true dark, false light, nil the Mac's.
    public var forcesDark: Bool? {
        switch self {
        case .automatic: nil
        case .light: false
        case .dark: true
        }
    }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    /// What Chromium's colour mode takes: 0 the system's, 1 light, 2 dark.
    public var chromiumMode: Int {
        switch self {
        case .automatic: 0
        case .light: 1
        case .dark: 2
        }
    }
}

