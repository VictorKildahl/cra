import CraCore
import Foundation
import Testing

/// Where a Little Window's page goes when it is sent to a space (GitHub #92).
struct SpaceWindowTests {
    let a = UUID(), b = UUID(), c = UUID()
    let victor = UUID(), jysk = UUID(), work = UUID()

    /// Arc: window A shows Victor and was used last, window B shows JYSK; JYSK goes to B.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/92"))
    func aWindowShowingTheSpaceTakesThePage() {
        #expect(SpaceWindow.window(for: jysk, windows: [(a, victor), (b, jysk)], lastUsed: a) == b)
        #expect(SpaceWindow.window(for: victor, windows: [(a, victor), (b, jysk)], lastUsed: a) == a)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/92"))
    func otherwiseTheWindowInUseLastSwitches() {
        #expect(SpaceWindow.window(for: work, windows: [(b, jysk), (a, victor)], lastUsed: a) == a)
        // The window in use can be hidden (the last one closed), so not in the list.
        #expect(SpaceWindow.window(for: work, windows: [], lastUsed: a) == a)
    }

    /// Of several windows on the space, the one in use last, else the frontmost.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/92"))
    func severalWindowsOnTheSpace() {
        #expect(SpaceWindow.window(for: jysk, windows: [(b, jysk), (c, jysk), (a, victor)], lastUsed: c) == c)
        #expect(SpaceWindow.window(for: jysk, windows: [(c, jysk), (b, jysk), (a, victor)], lastUsed: a) == c)
    }
}
