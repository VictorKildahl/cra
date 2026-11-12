import CoreGraphics
import Foundation
import Testing
@testable import CraCore

struct MusicNotesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303"), arguments: [
        "https://music.youtube.com/watch?v=abc",
        "https://open.spotify.com/track/1",
        "https://spotify.com/",
        "https://music.apple.com/us/album/1",
        "https://soundcloud.com/artist/track",
        "https://artist.bandcamp.com/album/x",
        "https://listen.tidal.com/",
        "https://www.pandora.com/station/play",
        "https://www.nts.live/radio",
        "https://MUSIC.YouTube.com/",
    ])
    func arcsMusicSites(url: String) {
        #expect(MusicNotes.isMusicSite(url))
    }

    /// A video site, a look-alike host and a host that only ends in a music site's letters.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303"), arguments: [
        "https://www.youtube.com/watch?v=abc",
        "https://youtube.com/",
        "https://apple.com/music",
        "https://notspotify.com/",
        "https://spotify.com.example.org/",
        "https://example.org/?next=spotify.com",
        "cra://settings",
        "about:blank",
        "",
        "not a url",
    ])
    func otherSites(url: String) {
        #expect(!MusicNotes.isMusicSite(url))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303")) func playsOnlyWhatCanBeHeardOnAMusicSite() {
        let music = "https://open.spotify.com/", video = "https://www.youtube.com/watch?v=abc"
        #expect(MusicNotes.plays(url: music, soundPlaying: true), "muted or not: a muted tab's sound still plays")
        #expect(!MusicNotes.plays(url: music, soundPlaying: false), "paused, even during the speaker's audible hold")
        #expect(!MusicNotes.plays(url: video, soundPlaying: true))
    }

    /// Single notes appear more often than pairs; notes grow and fade over their lifetime.
    @Test func emitterValues() {
        #expect(MusicNotes.Shape.allCases.map(MusicNotes.birthRate) == [1.4, 1])
        #expect(1 + MusicNotes.alphaSpeed * MusicNotes.lifetime == 0)
        #expect(MusicNotes.scale + MusicNotes.scaleSpeed * CGFloat(MusicNotes.lifetime) == 2)
    }

    @Test func inkStandsOutOnTheTile() {
        #expect(MusicNotes.ink(dark: true) == (1, 0.8))
        #expect(MusicNotes.ink(dark: false) == (0, 0.3))
    }

    /// The emitter sits on the top edge of the 16 pt icon in the middle of the cell, and the
    /// view around it leaves 30 pt on every side of the tile.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303")) func fieldIsCentredOnTheIconsTopEdge() {
        let tile = CGRect(x: 59, y: 55, width: 51, height: 47)
        let field = MusicNotes.field(over: tile)
        #expect(field == CGRect(x: 29, y: 17, width: 111, height: 107))
        #expect(CGPoint(x: field.midX, y: field.midY) == CGPoint(x: tile.midX, y: tile.midY - 8))
    }
}
