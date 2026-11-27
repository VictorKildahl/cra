import Foundation
import Observation

/// Arc's "now playing" player at the bottom of the sidebar (issue #33): every tab of the
/// window that played sound since it loaded, oldest first. Only sound Chromium's media session
/// can control counts, as Arc's player follows that session: a notification ding (under 5 s)
/// or Web Audio alone makes no card (#411). A tab stays listed while paused
/// and leaves when it is dismissed, closes, sleeps, or navigates while quiet. The sidebar
/// shows the ones that aren't on screen. Fed by BrowserManager.
@MainActor @Observable
final class NowPlaying {
    struct Entry: Equatable, Identifiable {
        let id: UUID
        var playing: Bool
        /// The page registered media session handlers for these (else the buttons are dimmed).
        var hasPrevious = false
        var hasNext = false
        /// A video plays: the card offers Picture in Picture.
        var hasVideo = false
        /// The tab's media volume (Arc's volume drawer), 0...1.
        var volume = 1.0
        /// What the page's media session and media element said at the last read (the island player,
        /// Discussion #761), and when on the app's clock. Only read while that player is chosen.
        var media: NowPlayingMedia?
        var mediaReadAt: TimeInterval = 0

        /// Where the media is, moved on since the read while it plays.
        var clock: NowPlayingClock? {
            guard let m = media, let p = m.position else { return nil }
            return NowPlayingClock(position: p, duration: m.duration, rate: m.rate, playing: playing && !m.paused, readAt: mediaReadAt)
        }
    }

    /// `skip` moves the media by seconds (negative: back), `seek` puts it at seconds from the start, and
    /// `refreshMedia` reads the page's media session again (the island player).
    enum Action { case togglePlayback, previous, next, toggleMute, dismiss, show, pictureInPicture, setVolume(Double), skip(Double), seek(Double), refreshMedia }

    var entries: [Entry] = []
    /// Tabs in the window's panes, and tabs whose video is in Picture in Picture: no card.
    var onScreen: Set<UUID> = []
    var pictureInPicture: Set<UUID> = []
    @ObservationIgnored var perform: (UUID, Action) -> Void = { _, _ in }

    /// Oldest first, as Arc stacks them (the newest is the front card).
    var shown: [Entry] { entries.filter { !onScreen.contains($0.id) && !pictureInPicture.contains($0.id) } }

    func update(_ id: UUID, _ change: (inout Entry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries[i]
        change(&e)
        if e != entries[i] { entries[i] = e }
    }

    func remove(_ id: UUID) {
        if entries.contains(where: { $0.id == id }) { entries.removeAll { $0.id == id } }
    }
}
