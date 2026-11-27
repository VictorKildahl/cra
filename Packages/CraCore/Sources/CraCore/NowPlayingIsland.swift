import Foundation

/// Discussion #761, not in Arc: how the now-playing player at the bottom of the sidebar looks. `.arc` is Arc's
/// cards (NowPlayingMetrics, the default). `.island` is a slim bar after Yab's player (yetanotherbrowser/yab,
/// Apache-2.0) in Arc's card colours: the artwork, the title and artist on one line and level bars at rest;
/// hovering opens it to the artwork, a progress bar, times and 15-second skips. It keeps Arc's close, Picture in
/// Picture and volume drawer, and Arc's stack for several players.
public enum NowPlayingStyle: String, Codable, Sendable, CaseIterable {
    case arc
    case island
}

/// What a page's media session (`navigator.mediaSession.metadata`) and its playing media element say, as
/// PageScript's isolated world reads them (`NowPlayingMedia.script`). Everything is optional: a page without a
/// media session has only its element's clock, and audio a page made with `new Audio()` and never added has
/// no element to read.
public struct NowPlayingMedia: Equatable, Sendable {
    public struct Artwork: Equatable, Sendable {
        public var src: String
        public var sizes: String
        public init(src: String, sizes: String = "") {
            self.src = src
            self.sizes = sizes
        }

        /// The widest size it lists ("96x96 192x192", SoundCloud's "t500x500"), 0 for none or "any".
        var width: Int {
            sizes.split(separator: " ").compactMap { Int(String(($0.lowercased().split(separator: "x").first ?? "").drop { !$0.isNumber })) }.max() ?? 0
        }
    }

    public var title: String
    public var artist: String
    public var album: String
    public var artwork: [Artwork]
    /// Seconds into the media; nil when no element says.
    public var position: Double?
    /// Its length in seconds: nil when unknown, `.infinity` for a live stream.
    public var duration: Double?
    public var rate: Double
    public var paused: Bool

    public init(title: String = "", artist: String = "", album: String = "", artwork: [Artwork] = [],
                position: Double? = nil, duration: Double? = nil, rate: Double = 1, paused: Bool = false) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.position = position
        self.duration = duration
        self.rate = rate
        self.paused = paused
    }

    /// Run in the page's isolated world: the media session's metadata (DOM objects are shared between worlds)
    /// and the element that plays, else the one that played, else the first. A page whose media session names no
    /// artwork (Bandcamp sets none) offers its og:image, an album's cover there. A YouTube live stream, whose
    /// element says a finite length, is reported live while YouTube's player shows its Live badge. A JSON string, or "" when there is
    /// neither metadata nor an element. `duration` is -1 for a live stream (Infinity has no JSON).
    public static let script = """
    (() => {
      const md = navigator.mediaSession ? navigator.mediaSession.metadata : null;
      const media = [...document.querySelectorAll('video,audio')];
      const m = media.find(x => !x.paused && !x.ended) ?? media.find(x => x.currentTime > 0) ?? media[0];
      if (!md && !m) return '';
      let art = md && md.artwork ? [...md.artwork].map(a => ({ src: String(a.src || ''), sizes: String(a.sizes || '') })) : [];
      const og = document.querySelector('meta[property="og:image"]');
      if (!art.length && og && og.content) art = [{ src: new URL(og.content, location.href).href, sizes: '' }];
      // YouTube gives a live stream a finite length (its rewind window, hours long); its player's Live badge shows.
      const badge = document.querySelector('.ytp-live-badge');
      const d = m ? (badge && badge.getClientRects().length ? Infinity : m.duration) : NaN;
      return JSON.stringify({
        title: md ? String(md.title || '') : '', artist: md ? String(md.artist || '') : '', album: md ? String(md.album || '') : '',
        artwork: art.slice(0, 16),
        position: m && isFinite(m.currentTime) ? m.currentTime : null,
        duration: m ? (d === Infinity ? -1 : isFinite(d) && d > 0 ? d : null) : null,
        rate: m ? m.playbackRate : 1, paused: m ? m.paused : true
      });
    })()
    """

    /// The script's answer; nil for "" or anything else.
    public static func parse(_ json: String) -> NowPlayingMedia? {
        guard let data = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func text(_ key: String) -> String {
            String((o[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        }
        let art = (o["artwork"] as? [[String: Any]] ?? []).compactMap { a -> Artwork? in
            guard let src = a["src"] as? String, !src.isEmpty, src.count <= 4096 else { return nil }
            return Artwork(src: src, sizes: a["sizes"] as? String ?? "")
        }
        let duration: Double? = (o["duration"] as? Double).flatMap { $0 < 0 ? .infinity : $0 > 0 ? $0 : nil }
        let position = (o["position"] as? Double).map { max(0, $0) }
        let rate = (o["rate"] as? Double).flatMap { $0.isFinite ? $0 : nil } ?? 1
        return NowPlayingMedia(title: text("title"), artist: text("artist"), album: text("album"), artwork: art,
                               position: position, duration: duration, rate: rate, paused: o["paused"] as? Bool ?? false)
    }

    /// The artwork to show `pixels` wide: the smallest at least that wide, else the widest. One with no size
    /// (or "any") counts as wide enough but comes after the sized ones, since it can be anything.
    public func artworkURL(forPixels pixels: Int) -> String? {
        guard !artwork.isEmpty else { return nil }
        let sized = artwork.filter { $0.width > 0 }
        if let fit = sized.filter({ $0.width >= pixels }).min(by: { $0.width < $1.width }) { return fit.src }
        if let any = artwork.first(where: { $0.width == 0 }) { return any.src }
        return sized.max(by: { $0.width < $1.width })?.src
    }
}

/// Where the media is between reads: the last read moved on by the time since at its rate while it plays,
/// held at its end.
public struct NowPlayingClock: Equatable, Sendable {
    public var position: Double
    public var duration: Double?
    public var rate: Double
    public var playing: Bool
    /// When it was read, on the app's clock.
    public var readAt: TimeInterval

    public init(position: Double, duration: Double?, rate: Double = 1, playing: Bool, readAt: TimeInterval) {
        self.position = position
        self.duration = duration
        self.rate = rate
        self.playing = playing
        self.readAt = readAt
    }

    public func position(at now: TimeInterval) -> Double {
        let moved = playing ? max(0, now - readAt) * max(0, rate) : 0
        let p = position + moved
        if let d = duration, d.isFinite { return min(max(0, p), d) }
        return max(0, p)
    }

    /// How far through it is, 0…1; nil without a finite length.
    public func fraction(at now: TimeInterval) -> Double? {
        guard let d = duration, d.isFinite, d > 0 else { return nil }
        return min(1, max(0, position(at: now) / d))
    }
}

/// The island's decisions: what the open card's progress row and transport buttons show.
public enum NowPlayingIsland {
    /// Skips when the page has no tracks to move between, as Yab's: 15 seconds.
    public static let skipSeconds: Double = 15

    public enum Transport: Equatable, Sendable {
        case previousTrack, nextTrack, skipBack, skipAhead
    }

    /// Each side's button: the page's previous/next track where it handles them (a playlist), else a 15-second
    /// skip when there is something to skip through, else the track button, dimmed.
    public static func transport(hasPrevious: Bool, hasNext: Bool, canSeek: Bool) -> (leading: Transport, trailing: Transport) {
        (hasPrevious || !canSeek ? .previousTrack : .skipBack, hasNext || !canSeek ? .nextTrack : .skipAhead)
    }

    /// How the open card fits its width (Victor, 26 Nov 2026: a narrow sidebar squeezed the title to "Big" and
    /// ran the side buttons into the skips). From 220 pt it is laid out as designed: 48 pt artwork with the title
    /// beside it, three 36 pt buttons 48 pt apart between the tab's icon and the volume button. Narrower, it
    /// stacks: 40 pt artwork with Picture in Picture and close beside it, the title and artist under it at full
    /// width, and the buttons row first draws closer (32 pt, 40 apart), then leaves out the tab's icon (the
    /// artwork goes back to the tab too), and at the very narrowest the volume button.
    public struct OpenLayout: Equatable, Sendable {
        public var stacked: Bool
        public var height: Double
        public var cover: Double
        public var button: Double
        public var pitch: Double
        public var showsBack: Bool
        public var showsVolume: Bool
        /// Where the three buttons' middle one is centred, from the card's left.
        public var transportCentre: Double
    }

    public static let wideWidth: Double = 220
    static let sideButton: Double = 28, sideMargin: Double = 10, sideGap: Double = 6

    public static func openLayout(width w: Double) -> OpenLayout {
        let stacked = w < wideWidth
        func needs(_ button: Double, _ pitch: Double, back: Bool, volume: Bool) -> Double {
            2 * sideMargin + (back ? sideButton + sideGap : 0) + (volume ? sideButton + sideGap : 0) + 2 * pitch + button
        }
        let options: [(Double, Double, Bool, Bool)] = [(36, 48, true, true), (32, 40, true, true), (32, 40, false, true),
                                                       (32, 40, false, false), (28, 34, false, false)]
        let pick = options.first { needs($0.0, $0.1, back: $0.2, volume: $0.3) <= w } ?? options[options.count - 1]
        let left = sideMargin + (pick.2 ? sideButton + sideGap : 0)
        let right = w - sideMargin - (pick.3 ? sideButton + sideGap : 0)
        return OpenLayout(stacked: stacked, height: stacked ? 178 : 144, cover: stacked ? 40 : 48, button: pick.0, pitch: pick.1,
                          showsBack: pick.2, showsVolume: pick.3, transportCentre: (left + right) / 2)
    }

    /// Seeking needs a position and a finite length (a live stream has neither).
    public static func canSeek(_ media: NowPlayingMedia?) -> Bool {
        guard let m = media, m.position != nil, let d = m.duration else { return false }
        return d.isFinite
    }

    public enum Progress: Equatable, Sendable {
        /// No length known: the open card shows no progress row.
        case hidden
        /// A live stream: "Live" where the times go, no bar to drag.
        case live
        /// "1:23" on the left, "-2:05" on the right, the bar filled to `fraction`.
        case times(elapsed: String, remaining: String, fraction: Double)
    }

    public static func progress(_ clock: NowPlayingClock?, at now: TimeInterval) -> Progress {
        guard let clock, let d = clock.duration else { return .hidden }
        guard d.isFinite else { return .live }
        let p = clock.position(at: now)
        return .times(elapsed: timeLabel(p), remaining: "-" + timeLabel(max(0, d - p)), fraction: clock.fraction(at: now) ?? 0)
    }

    /// "0:07", "12:34", "1:02:03".
    public static func timeLabel(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    /// Where a drag at `fraction` (0…1) of the bar seeks to.
    public static func seekTarget(fraction: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, fraction), 1) * duration
    }

    /// What the title line says: the media session's title, else the tab's own title without the mark some sites
    /// put in front of it while they play (Bandcamp's "▶︎ Minecraft - Volume Alpha | C418"): the island says that.
    public static func title(_ media: NowPlayingMedia?, tabTitle: String) -> String {
        let t = media?.title ?? ""
        return t.isEmpty ? withoutPlayingMark(tabTitle) : t
    }

    /// ▶ ► ▸ ⏵ 🔊 🔉 ♪ ♫ (with or without a variation selector) and the spaces after them, at the start only.
    static func withoutPlayingMark(_ title: String) -> String {
        let marks: Set<UInt32> = [0x25B6, 0x25BA, 0x25B8, 0x23F5, 0x1F50A, 0x1F509, 0x266A, 0x266B, 0xFE0E, 0xFE0F, 0x20, 0xA0]
        let rest = title.unicodeScalars.drop { marks.contains($0.value) }
        return rest.isEmpty ? title : String(String.UnicodeScalarView(rest))
    }
}
