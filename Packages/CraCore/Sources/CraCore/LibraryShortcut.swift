import Foundation

/// What a Library shortcut does (GitHub #649). Arc's are show/hide toggles, like ⌘S for the sidebar:
/// ⇧⌘L (Open Library) and ⇧⌘J (View Downloads) open the Library, and pressed again they close it.
/// A page's shortcut while the Library shows another page goes to that page instead of closing it.
public enum LibraryShortcut {
    public enum Step: Equatable, Sendable {
        case show
        case close
    }

    /// - Parameters:
    ///   - requested: the page the shortcut names; nil for Open Library, which shows the page last shown.
    ///   - shown: the page on screen; nil while the Library is closed.
    public static func step<Page: Equatable>(requested: Page?, shown: Page?) -> Step {
        guard let shown else { return .show }
        if let requested, requested != shown { return .show }
        return .close
    }
}
