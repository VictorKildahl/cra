import Foundation

/// When a page left behind may go into its automatic Picture in Picture. Arc opens it when you switch to another tab,
/// and not when you switch to another space (#703): the page stays in its space, still playing, as it does when you
/// go to another app.
public enum AutoPictureInPictureMoment {
    /// `from`: the space whose pages were on screen; `to`: the space on screen now. Without a space before (the
    /// window's first pages), it's an ordinary switch.
    public static func opensOnLeaving(from: UUID?, to: UUID?) -> Bool {
        guard let from, let to else { return true }
        return from == to
    }
}
