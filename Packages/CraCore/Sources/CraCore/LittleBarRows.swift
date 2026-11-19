/// What the command bar's rows for pages kept elsewhere do in a Little Window (#599).
///
/// The browser window's bar lists open tabs ("Switch to Tab") and archived pages ("Restore"), before
/// anything is typed too, and a pick takes you to that tab in the browser window. A Little Window's
/// bar listed the same rows, so picking a page from its list, which looks like any other, brought
/// the browser window forward and left the Little Window behind; whether it did depended on the
/// page being open in a tab or archived, which the list doesn't make obvious. Little Arc keeps you in
/// its window until you move the page with ⌘O (Open in <space>), so there those rows load their
/// page in the window, as history rows do. Not checked against live Arc: what Little Arc's own bar
/// lists for open tabs.
public enum LittleBarRows {
    /// A row the bar lists for a page that is somewhere else.
    public enum Row: Equatable, Sendable {
        /// A tab open in a browser window.
        case openTab
        /// A page in the archive (closed Little Window pages go there too).
        case archivedPage
    }

    public enum Action: Equatable, Sendable {
        /// The page loads in the window the bar belongs to; the row reads as a plain page row.
        case loadInWindow
        /// The browser window switches to the tab, or restores the page, as its own bar does.
        case browserWindow
    }

    /// `tabsScope`: the bar was scoped to a space's open tabs ("%" then Tab), which asks for a tab.
    /// A Peek is a look at a link over a tab of the browser window, whose tabs it switches between
    /// as that window's bar does (#379).
    public static func action(for row: Row, in window: CommandBarOpening.Window, tabsScope: Bool) -> Action {
        switch window {
        case .littleWindow: return tabsScope ? .browserWindow : .loadInWindow
        case .browser, .peek: return .browserWindow
        }
    }
}
