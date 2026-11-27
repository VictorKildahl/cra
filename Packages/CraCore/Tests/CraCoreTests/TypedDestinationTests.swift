import CraCore
import Foundation
import Testing

/// Where an address typed in ⌘T opens, and the profile it counts in for typed completion.
struct TypedDestinationTests {
    let home = UUID(), work = UUID()

    /// An address Air Traffic Control sends to a space on another profile counts there, not in the profile it was
    /// typed in, so the typing profile doesn't complete an address that never opened in it, as in Arc (#864).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/864"))
    func aRoutedAddressCountsInTheSpaceItOpensIn() {
        let routed = TypedDestination.of(loadsInSelectedTab: false, route: work, focused: home)
        #expect(routed == .routed(space: work))
        #expect(routed.space(focused: home) == work)
    }

    /// The rest open in the space in use and count there: no route, a route to the space in use, and ⌘L or an empty
    /// pane, which load in the tab in front whatever the routes say (#421).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/864"))
    func everythingElseCountsInTheSpaceInUse() {
        #expect(TypedDestination.of(loadsInSelectedTab: false, route: nil, focused: home) == .newTab)
        #expect(TypedDestination.of(loadsInSelectedTab: false, route: home, focused: home) == .newTab)
        #expect(TypedDestination.of(loadsInSelectedTab: true, route: work, focused: home) == .selectedTab)
        for d in [TypedDestination.newTab, .selectedTab] { #expect(d.space(focused: home) == home) }
    }
}
