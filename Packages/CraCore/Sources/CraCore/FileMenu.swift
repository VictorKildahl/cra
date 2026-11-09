import Foundation

/// The menu bar's File menu, row for row as Arc 1.172.1 has it (read over Accessibility and
/// captured with and without a tab selected, 9 Nov 2026, GitHub #279). Rows are key-action
/// identifiers; a separator goes between sections.
///
///     New Tab…, New Window, Blank Window, New Incognito Window, New Little Arc Window,
///     Restore Last Closed Tab
///     ──
///     Open Command Bar
///     ──
///     New Profile, New Easel
///     ──
///     Close Window, Close Tab (only while a tab is selected)
///     ──
///     Share…, Capture…, Capture Full Page, Capture in Portrait Mode, Save Page As, Print
///
/// Arc also carries New Note, Archive Tab and Send to Dia as hidden rows; they never show, so
/// Cra leaves them out. Arc keeps New Space… in the Spaces menu and New Folder… in Tabs.
public enum FileMenu {
    public static let sections: [[String]] = [
        ["newTab", "newWindow", "newBlankWindow", "newIncognitoWindow", "newLittleWindow", "reopenClosedTab"],
        ["editURL"],
        ["newProfile", "newEasel"],
        ["closeWindow", "closeTab"],
        ["share", "capturePage", "captureFullPage", "capturePortrait", "savePageAs", "print"],
    ]

    /// Whether a row shows. Arc hides Close Tab while no tab is selected (its window shows the
    /// command bar over an empty page); ⌘W still closes the window then.
    public static func shows(_ id: String, tabSelected: Bool) -> Bool {
        id == "closeTab" ? tabSelected : true
    }

    /// The rows that show, in sections, as the menu draws them.
    public static func shown(tabSelected: Bool) -> [[String]] {
        sections.map { $0.filter { shows($0, tabSelected: tabSelected) } }.filter { !$0.isEmpty }
    }
}
