/// A main window's full screen for a page's own (a video's full-screen button, requestFullscreen), as in Arc
/// and Chrome: the window goes full screen with the page, and comes back when the page leaves it (Esc, the
/// player's button, or its tab closing with ⌘W, #636). A window the user had made full screen first stays.
public struct PageFullscreenWindow: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case stay, enter, leave
    }

    /// The window is full screen because a page asked: it is not remembered for the next launch (#426).
    public private(set) var enteredForPage = false

    public init() {}

    /// A page in the window went in or out of its full screen. `closing`: the window is closing or being put
    /// in the menu bar, which takes it out of full screen itself.
    public mutating func page(fullscreen: Bool, windowFullscreen: Bool, closing: Bool) -> Step {
        if fullscreen {
            guard !windowFullscreen, !closing else { return .stay }
            enteredForPage = true
            return .enter
        }
        guard enteredForPage, windowFullscreen, !closing else { return .stay }
        enteredForPage = false
        return .leave
    }

    /// The window left full screen, however it did.
    public mutating func windowLeftFullScreen() { enteredForPage = false }
}
