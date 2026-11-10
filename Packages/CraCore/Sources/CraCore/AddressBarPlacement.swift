/// Where the address bar sits (GitHub #305): Arc's View ▸ Show Toolbar, named for what it moves.
/// Onboarding's "Make it yours" step and Settings ▸ Tabs ▸ Address Bar offer the same two
/// choices in the same words, so the setting can be found again after onboarding.
public enum AddressBarPlacement: String, CaseIterable, Sendable {
    /// Arc's default: the URL is the first row of the sidebar.
    case sidebar
    /// Arc's toolbar above the page (URL, copy link, DevTools).
    case toolbar

    /// The name under onboarding's layout picture.
    public var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .toolbar: "Toolbar"
        }
    }

    /// Where that puts the address bar, as Settings lists it.
    public var detail: String {
        switch self {
        case .sidebar: "At the top of the sidebar"
        case .toolbar: "In a toolbar above the page"
        }
    }
}

extension AppSettings {
    /// `showToolbar` as a placement. settings.json keeps `showToolbar`, so files written
    /// before and after #305 read the same.
    public var addressBarPlacement: AddressBarPlacement {
        get { showToolbar ? .toolbar : .sidebar }
        set { showToolbar = newValue == .toolbar }
    }
}
