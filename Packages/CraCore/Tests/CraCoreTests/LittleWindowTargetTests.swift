import CraCore
import Foundation
import Testing

/// The space a Little Window's "Open in" names (#316).
struct LittleWindowTargetTests {
    let personal = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    let random = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    let work = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!

    /// Nothing picked: the space of the window used last, as Arc's Little Arc does (#92).
    @Test func followsTheWindowUsedLastUntilASpaceIsPicked() {
        let t = LittleWindowTarget()
        #expect(t.space(lastUsed: personal) == personal)
        #expect(t.space(lastUsed: random) == random)
        #expect(t.picked == nil)
    }

    /// A space picked in the Little Window stays, whichever space the browser window switches to
    /// (#316). It is that window's only: the next Little Window follows the window used last again,
    /// so a link from another app doesn't open in a space (and its sign-ins) picked earlier. A
    /// Little Window that names its space (cra://open, an Air Traffic Control route) keeps it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func aPickedSpaceStaysInItsWindowOnly() {
        var first = LittleWindowTarget()
        first.pick(random)
        #expect(first.space(lastUsed: personal) == random)
        #expect(first.space(lastUsed: work) == random)
        #expect(LittleWindowTarget().space(lastUsed: personal) == personal)
        #expect(LittleWindowTarget(requested: work).space(lastUsed: personal) == work)
    }

    /// A picked space that was deleted: back to the window used last.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func aDeletedSpaceIsForgotten() {
        var t = LittleWindowTarget()
        t.pick(random)
        t.forget { $0 != random }
        #expect(t.space(lastUsed: personal) == personal)
    }
}
