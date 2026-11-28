/// A hardware keyboard's shortcuts on the iPad (and an iPhone with a keyboard attached).
///
/// ⌘T opens the search for a new tab, as it does in Arc Search on the iPad. ⌘L opens it on the
/// page's address (Safari's key on the iPad too) and Escape puts the sheet away, as Cra's Mac
/// keys do.
public enum MobileKeyCommands {
    public enum Key: Equatable {
        case character(String)
        case escape
    }

    public enum Command: String, CaseIterable {
        case newTab, openLocation, closeSearch

        public var key: Key {
            switch self {
            case .newTab: .character("t")
            case .openLocation: .character("l")
            case .closeSearch: .escape
            }
        }

        /// Pressed with ⌘.
        public var withCommand: Bool { self != .closeSearch }

        public var title: String {
            switch self {
            case .newTab: "New Tab"
            case .openLocation: "Open Location"
            case .closeSearch: "Close Search"
            }
        }
    }

    public enum Effect: Equatable {
        /// The search sheet, empty; what is chosen opens in a new tab (the + pill).
        case search
        /// The search sheet with the shown page's address, selected (`MobileAddressEdit`).
        case editAddress
        case closeSearch
    }

    /// What `command` does now, or nil when it does nothing. A command that does nothing is not
    /// claimed, so its key still reaches the page: Escape closes a page's own dialog or video.
    /// `covered`: something else is over the browser (Settings, the page menu, onboarding, a summary).
    public static func effect(of command: Command, searching: Bool, hasPage: Bool, covered: Bool) -> Effect? {
        guard !covered else { return nil }
        switch command {
        case .newTab: return searching ? nil : .search
        case .openLocation: return searching ? nil : hasPage ? .editAddress : .search
        case .closeSearch: return searching ? .closeSearch : nil
        }
    }
}
