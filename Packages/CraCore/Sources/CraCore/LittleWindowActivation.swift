import Foundation

/// Whether a Little Window is a non-activating panel where it is (#581).
///
/// It opens as one, as Little Arc is, so it can come up over another app's full-screen Space (#186). A non-activating
/// panel never makes Cra the front app for the WindowServer, though: picked in Mission Control or App Exposé, Cra came
/// forward, and as Mission Control closed the WindowServer gave the front back to the app with an ordinary window on
/// that desktop (the terminal the link came from), over the Little Window. It kept Cra in front only when the browser
/// window was on the same desktop. So on a desktop, where an ordinary window can be, it becomes an ordinary panel.
public enum LittleWindowActivation {
    /// The kind of Space the window is on, as the WindowServer has it.
    public enum Space: Equatable {
        case desktop
        case fullScreen
        /// Several, none, or a kind the WindowServer didn't say.
        case unknown
    }

    /// The Space kind for the WindowServer's type number of each Space the window is on (CGSSpaceGetType: 0 a
    /// desktop, 4 a full-screen Space).
    public static func space(types: [Int32]) -> Space {
        guard types.count == 1 else { return .unknown }
        switch types[0] {
        case 0: return .desktop
        case 4: return .fullScreen
        default: return .unknown
        }
    }

    /// Whether the window stays non-activating on `space`: anywhere but a desktop, where it may be over another app's
    /// full screen. It never goes back to being one: a window on a desktop stays there.
    public static func staysNonActivating(on space: Space) -> Bool { space != .desktop }
}
