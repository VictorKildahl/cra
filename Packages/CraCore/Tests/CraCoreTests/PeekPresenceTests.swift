import CraCore
import Foundation
import Testing

/// A Peek belongs to the tab it came from (Arc's `modalByWindowContent`, GitHub #242).
struct PeekPresenceTests {
    static let pinned = UUID(), linked = UUID(), other = UUID()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/242"))
    func aPeekWaitsWhileAnotherTabIsOpenAndComesBackWithItsTab() {
        // A link from inside the Peek opened a tab: the Peek waits on the pinned tab.
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [Self.linked], tabExists: true) == .parked)
        // Back on the pinned tab, it is there again.
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [Self.pinned], tabExists: true) == .shown)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/242"))
    func aPeekGoesWithItsTab() {
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [Self.linked], tabExists: false) == .dropped)
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [Self.pinned], tabExists: false) == .dropped)
    }

    @Test func aPeekFromAPaneShowsWhileItsSplitIsOnScreen() {
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [Self.other, Self.pinned], tabExists: true) == .shown)
        #expect(PeekPresence.of(peekFrom: Self.pinned, onScreen: [], tabExists: true) == .parked)
    }

    @Test func aPeekFromNoTabStaysWhereItIs() {
        #expect(PeekPresence.of(peekFrom: nil, onScreen: [Self.linked], tabExists: false) == .shown)
    }
}
