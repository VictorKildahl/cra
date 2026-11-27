import Foundation
import Testing
@testable import CraCore

/// Discussion #761: the island player (after Yab's), an option next to Arc's cards.
@Suite struct NowPlayingIslandTests {
    // MARK: The setting

    /// Arc's cards by default; an older settings.json loads Arc's, and the choice isn't reported.
    @Test func arcByDefault() throws {
        #expect(AppSettings().nowPlayingStyle == .arc)
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.nowPlayingStyle == .arc)
        #expect(UsageStats.unreportedSettings.contains("nowPlayingStyle"))
    }

    /// Saved and read back; a style from a newer Cra loads Arc's instead of failing the file.
    @Test func savedAndReadBack() throws {
        var s = AppSettings()
        s.nowPlayingStyle = .island
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.nowPlayingStyle == .island)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"nowPlayingStyle":"bubble","nowPlayingTint":"theme"}"#.utf8))
        #expect(unknown.nowPlayingStyle == .arc)
        #expect(unknown.nowPlayingTint == .theme)
    }

    // MARK: What the page says

    @Test func readsTheMediaSessionAndTheElement() throws {
        let json = #"{"title":"  Slow Tides ","artist":"Harbour Lights","album":"Low Season","artwork":[{"src":"https://x.test/a96.png","sizes":"96x96"},{"src":"https://x.test/a512.png","sizes":"512x512"}],"position":72.5,"duration":234,"rate":1,"paused":false}"#
        let m = try #require(NowPlayingMedia.parse(json))
        #expect(m.title == "Slow Tides")
        #expect(m.artist == "Harbour Lights")
        #expect(m.album == "Low Season")
        #expect(m.artwork.count == 2)
        #expect(m.position == 72.5)
        #expect(m.duration == 234)
        #expect(!m.paused)
    }

    /// A live stream says -1 (Infinity has no JSON); an element with no length yet says null; a page with
    /// neither metadata nor an element says "" and has nothing to show.
    @Test func liveStreamsAndUnknownLengths() throws {
        #expect(try #require(NowPlayingMedia.parse(#"{"position":12,"duration":-1}"#)).duration == .infinity)
        #expect(try #require(NowPlayingMedia.parse(#"{"position":0,"duration":null}"#)).duration == nil)
        #expect(NowPlayingMedia.parse("") == nil)
        #expect(NowPlayingMedia.parse("not json") == nil)
    }

    /// Artwork with an empty or absurdly long address is left out.
    @Test func dropsUnusableArtwork() throws {
        let long = String(repeating: "a", count: 5000)
        let m = try #require(NowPlayingMedia.parse(#"{"artwork":[{"src":""},{"src":"\#(long)"},{"src":"https://x.test/ok.png"}]}"#))
        #expect(m.artwork.map(\.src) == ["https://x.test/ok.png"])
    }

    /// The smallest picture wide enough for the pixels wanted, else the widest; an unsized one counts as wide
    /// enough only after the sized ones.
    @Test func choosesTheArtworkThatFits() {
        let m = NowPlayingMedia(artwork: [.init(src: "s96", sizes: "96x96"), .init(src: "s512", sizes: "512x512"),
                                          .init(src: "s256", sizes: "256x256")])
        #expect(m.artworkURL(forPixels: 112) == "s256")
        #expect(m.artworkURL(forPixels: 64) == "s96")
        #expect(m.artworkURL(forPixels: 1024) == "s512")
        let unsized = NowPlayingMedia(artwork: [.init(src: "s96", sizes: "96x96"), .init(src: "any", sizes: "any")])
        #expect(unsized.artworkURL(forPixels: 112) == "any")
        #expect(unsized.artworkURL(forPixels: 64) == "s96")
        #expect(NowPlayingMedia().artworkURL(forPixels: 112) == nil)
        #expect(NowPlayingMedia(artwork: [.init(src: "a", sizes: "48x48 192x192")]).artwork[0].width == 192)
    }

    /// SoundCloud lists its covers as "t500x500" … "t80x80": read as sizes, so the island loads the 120 px one,
    /// not the first.
    @Test func readsSoundCloudsSizes() {
        let sc = NowPlayingMedia(artwork: ["t500x500", "t300x300", "t250x250", "t120x120", "t80x80"].map { .init(src: $0, sizes: $0) })
        #expect(sc.artwork.map(\.width) == [500, 300, 250, 120, 80])
        #expect(sc.artworkURL(forPixels: 112) == "t120x120")
    }

    // MARK: The clock

    /// Between reads the position moves on at the media's rate while it plays, stays put while paused, and
    /// stops at the end.
    @Test func positionMovesOnBetweenReads() {
        let playing = NowPlayingClock(position: 10, duration: 60, rate: 1, playing: true, readAt: 100)
        #expect(playing.position(at: 102.5) == 12.5)
        #expect(playing.position(at: 99) == 10)
        #expect(playing.position(at: 500) == 60)
        #expect(playing.fraction(at: 100) == 10.0 / 60)
        let fast = NowPlayingClock(position: 10, duration: nil, rate: 2, playing: true, readAt: 0)
        #expect(fast.position(at: 3) == 16)
        #expect(fast.fraction(at: 3) == nil)
        let paused = NowPlayingClock(position: 10, duration: 60, rate: 1, playing: false, readAt: 0)
        #expect(paused.position(at: 30) == 10)
    }

    // MARK: The open card

    @Test func progressRow() {
        let clock = NowPlayingClock(position: 83, duration: 208, playing: false, readAt: 0)
        #expect(NowPlayingIsland.progress(clock, at: 0) == .times(elapsed: "1:23", remaining: "-2:05", fraction: 83.0 / 208))
        let live = NowPlayingClock(position: 83, duration: .infinity, playing: true, readAt: 0)
        #expect(NowPlayingIsland.progress(live, at: 0) == .live)
        let unknown = NowPlayingClock(position: 83, duration: nil, playing: true, readAt: 0)
        #expect(NowPlayingIsland.progress(unknown, at: 0) == .hidden)
        #expect(NowPlayingIsland.progress(nil, at: 0) == .hidden)
    }

    @Test func timeLabels() {
        #expect(NowPlayingIsland.timeLabel(7.9) == "0:07")
        #expect(NowPlayingIsland.timeLabel(754) == "12:34")
        #expect(NowPlayingIsland.timeLabel(3723) == "1:02:03")
        #expect(NowPlayingIsland.timeLabel(-4) == "0:00")
        #expect(NowPlayingIsland.timeLabel(.nan) == "0:00")
    }

    /// A playlist's own previous/next win; without them a seekable track gets 15-second skips; with neither
    /// the track buttons stay, dimmed.
    @Test func transportButtons() {
        typealias T = NowPlayingIsland.Transport
        #expect(NowPlayingIsland.transport(hasPrevious: true, hasNext: true, canSeek: true) == (T.previousTrack, T.nextTrack))
        #expect(NowPlayingIsland.transport(hasPrevious: false, hasNext: true, canSeek: true) == (T.skipBack, T.nextTrack))
        #expect(NowPlayingIsland.transport(hasPrevious: false, hasNext: false, canSeek: true) == (T.skipBack, T.skipAhead))
        #expect(NowPlayingIsland.transport(hasPrevious: false, hasNext: false, canSeek: false) == (T.previousTrack, T.nextTrack))
        #expect(NowPlayingIsland.skipSeconds == 15)
    }

    @Test func seekingNeedsAPositionAndAFiniteLength() {
        #expect(NowPlayingIsland.canSeek(NowPlayingMedia(position: 3, duration: 60)))
        #expect(!NowPlayingIsland.canSeek(NowPlayingMedia(position: 3, duration: .infinity)))
        #expect(!NowPlayingIsland.canSeek(NowPlayingMedia(position: nil, duration: 60)))
        #expect(!NowPlayingIsland.canSeek(nil))
        #expect(NowPlayingIsland.seekTarget(fraction: 0.25, duration: 200) == 50)
        #expect(NowPlayingIsland.seekTarget(fraction: 1.4, duration: 200) == 200)
        #expect(NowPlayingIsland.seekTarget(fraction: 0.5, duration: .infinity) == 0)
    }

    /// Wide enough, the open card is as designed; narrower, it stacks and its buttons row gives way in order,
    /// and the three buttons never reach the side buttons or the card's edges.
    @Test func openCardFitsItsWidth() {
        let wide = NowPlayingIsland.openLayout(width: 252)
        #expect(!wide.stacked && wide.height == 144 && wide.cover == 48)
        #expect(wide.button == 36 && wide.pitch == 48 && wide.showsBack && wide.showsVolume)
        #expect(wide.transportCentre == 126)
        let medium = NowPlayingIsland.openLayout(width: 205)
        #expect(medium.stacked && medium.cover == 40 && medium.height > 144)
        #expect(medium.button == 32 && medium.showsBack && medium.showsVolume)
        let narrow = NowPlayingIsland.openLayout(width: 147)
        #expect(narrow.stacked && !narrow.showsBack && !narrow.showsVolume)
        let tiny = NowPlayingIsland.openLayout(width: 100)
        #expect(tiny.button == 28)
        for w in stride(from: 100.0, through: 400, by: 1) {
            let l = NowPlayingIsland.openLayout(width: w)
            let first = l.transportCentre - l.pitch - l.button / 2, last = l.transportCentre + l.pitch + l.button / 2
            let left = l.showsBack ? 10 + 28 + 6 : 10.0, right = w - (l.showsVolume ? 10 + 28 + 6 : 10)
            if w >= 118 { #expect(first >= left - 0.001 && last <= right + 0.001, "width \(w)") }
            #expect(l.stacked == (w < 220))
        }
    }

    @Test func titleFallsBackToTheTab() {
        #expect(NowPlayingIsland.title(NowPlayingMedia(title: "Slow Tides"), tabTitle: "Music") == "Slow Tides")
        #expect(NowPlayingIsland.title(NowPlayingMedia(), tabTitle: "Music") == "Music")
        #expect(NowPlayingIsland.title(nil, tabTitle: "Music") == "Music")
    }

    /// Bandcamp's tab says "▶︎ Minecraft - Volume Alpha | C418" while it plays and sets no media session: the
    /// island's line leaves the mark out. Only at the start; a title that is nothing but the mark keeps it.
    @Test func titleLeavesOutASitesPlayingMark() {
        #expect(NowPlayingIsland.title(nil, tabTitle: "▶\u{FE0E} Minecraft - Volume Alpha | C418") == "Minecraft - Volume Alpha | C418")
        #expect(NowPlayingIsland.title(nil, tabTitle: "▶️ Song") == "Song")
        #expect(NowPlayingIsland.title(nil, tabTitle: "🔊 Radio") == "Radio")
        #expect(NowPlayingIsland.title(nil, tabTitle: "♫\u{A0}Mix") == "Mix")
        #expect(NowPlayingIsland.title(nil, tabTitle: "Side A ▶ Side B") == "Side A ▶ Side B")
        #expect(NowPlayingIsland.title(nil, tabTitle: "▶") == "▶")
        #expect(NowPlayingIsland.title(NowPlayingMedia(title: "▶ Intro"), tabTitle: "x") == "▶ Intro")
    }
}
