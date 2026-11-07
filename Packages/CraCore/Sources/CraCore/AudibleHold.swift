import Foundation

/// A WebKit tab's audible state as Chrome keeps it: on as sound starts, off only after `quiet`
/// seconds without sound, so a track change doesn't blink the tab's speaker or the sidebar's
/// now-playing card. WebKitBrowser feeds it WebKit's "playing audio" and tells its delegate
/// what each step says.
public struct AudibleHold: Equatable, Sendable {
    /// Chrome's AudioStreamMonitor holds a tab audible this long after its sound stops.
    public static let quiet: TimeInterval = 2

    /// What the tab does after a change of the page's sound.
    public enum Step: Equatable, Sendable {
        /// Tell the delegate the tab is audible.
        case announce
        /// Call `quietEnded()` after `quiet` seconds, unless sound comes back first.
        case holdThenQuiet
        case nothing
    }

    public private(set) var playing = false
    public private(set) var audible = false

    public init() {}

    /// The page's sound started or stopped. Sound coming back within the hold is announced
    /// again though the tab never went quiet: a pause from the sidebar's card has the card show
    /// paused already, and it learns of the page playing again only this way.
    public mutating func setPlaying(_ now: Bool) -> Step {
        let was = playing
        playing = now
        if now {
            guard !audible || !was else { return .nothing }
            audible = true
            return .announce
        }
        return audible ? .holdThenQuiet : .nothing
    }

    /// The hold ran out. True: tell the delegate the tab went quiet.
    public mutating func quietEnded() -> Bool {
        guard !playing, audible else { return false }
        audible = false
        return true
    }
}
