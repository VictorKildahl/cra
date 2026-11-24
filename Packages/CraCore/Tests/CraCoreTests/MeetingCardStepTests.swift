import CraCore
import Testing

/// One Join card for every Calendar favorite's tile (#758): a tile with no call on, or one off
/// screen, never takes down the card another tile put up.
@Suite struct MeetingCardStepTests {
    static func next(shown: String? = nil, owner: Bool = false, ownerOnScreen: Bool = false,
                     onScreen: Bool = true, meeting: String? = nil) -> MeetingCardStep {
        MeetingCardStep.next(shown: shown, ownerIsCaller: owner, ownerOnScreen: ownerOnScreen,
                             callerOnScreen: onScreen, meeting: meeting)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/758"))
    func aTileWithNoCallLeavesAnotherTilesCard() {
        // The Work space's Calendar (its own profile, nothing on) at the tick after Home's put the card up.
        #expect(Self.next(shown: "sync", owner: false, ownerOnScreen: true, onScreen: false, meeting: nil) == .leave)
        // Even on screen, in a second window.
        #expect(Self.next(shown: "sync", owner: false, ownerOnScreen: true, onScreen: true, meeting: nil) == .leave)
        // Or with a call of its own on: the first card stays, rather than the two taking turns each tick.
        #expect(Self.next(shown: "sync", owner: false, ownerOnScreen: true, onScreen: true, meeting: "standup") == .leave)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/758"))
    func theOwnerKeepsItsCardThroughTheTicks() {
        #expect(Self.next(shown: "sync", owner: true, ownerOnScreen: true, meeting: "sync") == .update)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/758"))
    func onlyATileOnScreenPutsTheCardUp() {
        #expect(Self.next(meeting: "sync") == .show)
        #expect(Self.next(onScreen: false, meeting: "sync") == .leave)
        #expect(Self.next() == .leave)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/758"))
    func theOwnerClosesItsCardWhenTheCallIsOverOrDismissed() {
        #expect(Self.next(shown: "sync", owner: true, ownerOnScreen: true, meeting: nil) == .close)
        // The next meeting comes up on a fresh card.
        #expect(Self.next(shown: "sync", owner: true, ownerOnScreen: true, meeting: "standup") == .show)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/758"))
    func aCardWhoseTileLeftTheScreenGoes() {
        // Its own tile, now in a space off screen.
        #expect(Self.next(shown: "sync", owner: true, ownerOnScreen: false, onScreen: false, meeting: "sync") == .close)
        // Another tile on screen takes over: the card moves beside it.
        #expect(Self.next(shown: "sync", owner: false, ownerOnScreen: false, onScreen: true, meeting: "sync") == .show)
        // One off screen just takes the stale card down.
        #expect(Self.next(shown: "sync", owner: false, ownerOnScreen: false, onScreen: false, meeting: "sync") == .close)
    }
}
