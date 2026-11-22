import Foundation

/// What a double click on a window's title bar does: System Settings ▸ Desktop & Dock "Double-click a window's title
/// bar to" (the global default AppleActionOnDoubleClick: Maximize, Fill, Minimize or Do Nothing; unset is Maximize).
/// Cra's window hides its real title bar under the content, so the parts that stand in for it run this themselves: the
/// sidebar's top, the strip above the card, and the toolbar's empty part (#685), as Arc's and other Mac apps' do.
public enum TitleBarDoubleClick: Equatable, Sendable {
    case zoom, minimize, nothing

    public init(setting: String?) {
        switch setting {
        case "None": self = .nothing
        case "Minimize": self = .minimize
        default: self = .zoom  // "Maximize", "Fill", unset
        }
    }

    /// Whether a press on a title-bar stand-in runs the action: the second click of a double click that stayed a
    /// click (a drag moves the window instead, #685).
    public static func runs(clickCount: Int, dragged: Bool) -> Bool { clickCount == 2 && !dragged }
}
