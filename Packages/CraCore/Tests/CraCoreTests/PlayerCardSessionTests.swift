import CraCore
import Testing

/// The sidebar player's card from Chromium's media session (#411): the reporter's cases.
struct PlayerCardSessionTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func mediaPlayingMakesAPlayingCard() {
        var s = PlayerCardSession()
        #expect(s.update(.active, controllable: true) == .show(playing: true))
        #expect(s.update(.ducking, controllable: true) == .show(playing: true), "ducked under another app's sound, still playing")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aTrackThatEndsRemovesTheCardAfterTheWait() {
        var s = PlayerCardSession()
        _ = s.update(.active, controllable: true)
        #expect(s.update(.inactive, controllable: false) == .removeLater)
        #expect(PlayerCardSession.endedDelay == 2.5)
    }

    /// A pause of any length keeps the card, shown paused; buffering and quiet stretches keep the
    /// session active, so the card stays playing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aPauseKeepsThePausedCard() {
        var s = PlayerCardSession()
        _ = s.update(.active, controllable: true)
        #expect(s.update(.suspended, controllable: true) == .show(playing: false))
        #expect(s.update(.active, controllable: true) == .show(playing: true))
    }

    /// A next track within the wait: the session is active again, which calls the removal off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aNewTrackWithinTheWaitKeepsTheCard() {
        var s = PlayerCardSession()
        _ = s.update(.active, controllable: true)
        #expect(s.update(.inactive, controllable: false) == .removeLater)
        #expect(s.update(.active, controllable: true) == .show(playing: true))
    }

    /// A ding after a pause resets Chromium's session (uncontrollable, then inactive): the card
    /// stays paused throughout.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aDingAfterAPauseLeavesThePausedCard() {
        var s = PlayerCardSession()
        _ = s.update(.active, controllable: true)
        _ = s.update(.suspended, controllable: true)
        #expect(s.update(.active, controllable: false) == .none)
        #expect(s.update(.inactive, controllable: false) == .none)
    }

    /// A ding after the media ended doesn't call the removal off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aDingAfterAnEndLeavesTheCardGoing() {
        var s = PlayerCardSession()
        _ = s.update(.active, controllable: true)
        #expect(s.update(.inactive, controllable: false) == .removeLater)
        #expect(s.update(.active, controllable: false) == .none)
        #expect(s.update(.inactive, controllable: false) == .none)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aDingOrWebAudioAloneMakesNoCard() {
        var s = PlayerCardSession()
        #expect(s.update(.active, controllable: false) == .none)
        #expect(s.update(.inactive, controllable: false) == .none)
    }
}
