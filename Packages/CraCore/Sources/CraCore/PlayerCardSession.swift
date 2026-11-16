import Foundation

/// A tab's sidebar player card, followed from the page's media session as Arc's MiniPlayer
/// holds it (#411), on an engine that reports the session (Chrome's framework; CEF and WebKit
/// pages follow the audible state).
///
/// Chromium's session as Chrome's global media controls see it:
/// - media over 5 s (or of unknown length) playing: active and controllable;
/// - paused: suspended, still controllable, however long;
/// - ended: the player leaves the session, which goes inactive (never controllable);
/// - a ding (under 5 s) or Web Audio: no controllable session. A ding in a tab whose media is
///   paused even resets the session, which then goes inactive once the ding ends.
///
/// So a card is made and shows playing only for a controllable active session, shows paused for
/// a controllable suspended one, and leaves `endedDelay` after a controllable session goes
/// inactive. Anything uncontrollable leaves the card as it is.
public struct PlayerCardSession: Equatable, Sendable {
    public enum State: Equatable, Sendable { case inactive, active, ducking, suspended }

    public enum Change: Equatable, Sendable {
        /// Leave the card (and a removal on its way) as it is.
        case none
        /// Make the card if the tab has none, and show it playing or paused. A removal on its way
        /// is called off.
        case show(playing: Bool)
        /// Remove the card after `endedDelay`, unless a later change calls it off.
        case removeLater
    }

    /// How long Chrome's media controls keep an ended session's item (kFreezeTimerDelay,
    /// media_session_notification_item.cc): a next track within it keeps the card.
    public static let endedDelay: TimeInterval = 2.5

    /// The session the tab last reported was controllable.
    public private(set) var controllable = false

    public init() {}

    public mutating func update(_ state: State, controllable now: Bool) -> Change {
        let was = controllable
        controllable = now
        guard now else {
            // Only the end of the session that had the card removes it: a ding's session
            // ending after a pause leaves the paused card.
            return state == .inactive && was ? .removeLater : .none
        }
        switch state {
        case .active, .ducking: return .show(playing: true)
        case .suspended: return .show(playing: false)
        case .inactive: return .removeLater
        }
    }
}
