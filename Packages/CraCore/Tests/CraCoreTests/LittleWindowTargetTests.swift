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

    /// A space picked in the Little Window stays, whichever space the browser window switches to,
    /// and the next Little Window of the session opens on it (#316).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func aPickedSpaceStaysAndCarriesToTheNextLittleWindow() {
        var session = LittleWindowSession()
        var first = LittleWindowTarget(session: session)
        first.pick(random, session: &session)
        #expect(first.space(lastUsed: personal) == random)
        #expect(first.space(lastUsed: work) == random)
        let next = LittleWindowTarget(session: session)
        #expect(next.space(lastUsed: personal) == random)
        // A Little Window that names its space (cra://open, an Air Traffic Control route) keeps it.
        let routed = LittleWindowTarget(session: session, requested: work)
        #expect(routed.space(lastUsed: personal) == work)
        // A pick in one Little Window doesn't move another that is open.
        var second = LittleWindowTarget(session: session)
        second.pick(work, session: &session)
        #expect(first.space(lastUsed: personal) == random)
        #expect(LittleWindowTarget(session: session).space(lastUsed: personal) == work)
    }

    /// A picked space that was deleted: back to the window used last.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/316"))
    func aDeletedSpaceIsForgotten() {
        var session = LittleWindowSession()
        var t = LittleWindowTarget(session: session)
        t.pick(random, session: &session)
        t.forget { $0 != random }
        session.forget { $0 != random }
        #expect(t.space(lastUsed: personal) == personal)
        #expect(LittleWindowTarget(session: session).space(lastUsed: personal) == personal)
    }
}
