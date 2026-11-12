import Foundation

/// Where a Peek's Expand button takes the peeked page (GitHub #380).
///
/// Arc's Expand always made the page a new Today tab. With Settings ▸ Links ▸ "⌘-click Expand opens
/// in the tab" on (`peekExpandInSourceTab`, off by default), a ⌘-click loads the page in the tab the
/// Peek came from instead, so a link from a pinned app stays in that app's tab. A pinned tab keeps
/// its pinned address, and Back in it returns to the page the Peek opened over.
public enum PeekExpand: Equatable, Sendable {
    /// A new Today tab with the Peek's live page (Arc's Expand).
    case newTab
    /// The tab the Peek came from loads the page; the Peek closes.
    case sourceTab

    /// `commandClick`: ⌘ was held on the click. `hasSourceTab`: the Peek came from a tab that is
    /// still there (an easel's Peek, from the Library, has none).
    public static func target(commandClick: Bool, hasSourceTab: Bool, settings: AppSettings) -> PeekExpand {
        commandClick && hasSourceTab && settings.peekExpandInSourceTab ? .sourceTab : .newTab
    }
}
