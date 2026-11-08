import Foundation

/// Whether a Peek is on screen. Arc keeps a Peek per tab: its window contents hold
/// `modalByWindowContent` (WindowContents/WindowContentState, Arc 1.172.1), and a Peek left by
/// opening a tab from inside it was there again, same page and scroll, back on its pinned tab
/// (GitHub #242, the reporter on Arc 1.172). So a Peek shows while the tab it came from is on
/// screen, waits hidden while another tab is, and goes when its tab closes.
public enum PeekPresence: Equatable, Sendable {
    case shown
    /// Hidden with its page alive, until its tab is on screen again.
    case parked
    /// Its tab is gone: the Peek closes.
    case dropped

    /// `source` is the tab the Peek came from (nil: none, the Peek stays as it is); `onScreen`
    /// the window's panes, the selected tab or its split.
    public static func of(peekFrom source: UUID?, onScreen: [UUID], tabExists: Bool) -> PeekPresence {
        guard let source else { return .shown }
        guard tabExists else { return .dropped }
        return onScreen.contains(source) ? .shown : .parked
    }
}
