import Foundation

/// Cra in front for its Picture in Picture window (#741).
///
/// macOS gives a trackpad pinch only to the app in front: with another app in front, a pinch over the window went
/// nowhere (a probe app, 24 Nov 2026: no pinch event reached a background app's window, its app-wide monitors or a
/// global monitor; brought forward, every one did). Arc 1.173.1 is the same: a pinch over its window does nothing
/// until a click on the window brings Arc forward (its menu bar shows Arc), and then it resizes. Cra's window is a
/// non-activating panel (#206), so a click left Cra in the background and the pinch still went nowhere. Now a press
/// on the window brings Cra forward, as Arc's does, without its browser windows: they stay behind the app the user
/// was in, and one that AppKit gives the keyboard as Cra comes forward isn't the user in it, so an automatic Picture
/// in Picture's video stays out. That holds until the user uses another of Cra's windows or Cra goes behind again.
public struct PictureInPictureFront: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Bring Cra forward now, for the window.
        case comeForward
        case none
    }

    /// Cra is in front for the window only: none of its other windows is in use.
    public private(set) var inFrontForWindow = false

    public init() {}

    /// A press on the window (its video or its controls).
    public mutating func pressed(craActive: Bool) -> Step {
        guard !craActive else { return .none }
        inFrontForWindow = true
        return .comeForward
    }

    /// A click or a key in another of Cra's windows: the user is using Cra.
    public mutating func craUsed() {
        inFrontForWindow = false
    }

    /// Cra went behind another app.
    public mutating func craLeft() {
        inFrontForWindow = false
    }

    /// Whether a browser window taking the keyboard means the user is back in it (its tab's automatic Picture in
    /// Picture video comes home then). Not while Cra came forward for the window only.
    public var browserKeyIsUse: Bool { !inFrontForWindow }
}
