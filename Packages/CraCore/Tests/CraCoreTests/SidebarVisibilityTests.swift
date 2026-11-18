import CraCore
import Testing

/// The sidebar stays visible when no tabs are open, matching Arc.
struct SidebarVisibilityTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/525"))
    func sidebarShownWhenTabSelectedFollowsUserVisible() {
        #expect(SidebarVisibility.isShown(userVisible: true, hasSelectedTab: true))
        #expect(!SidebarVisibility.isShown(userVisible: false, hasSelectedTab: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/525"))
    func sidebarAlwaysShownWhenNoTabSelected() {
        #expect(SidebarVisibility.isShown(userVisible: true, hasSelectedTab: false))
        #expect(SidebarVisibility.isShown(userVisible: false, hasSelectedTab: false),
                "Arc keeps the sidebar visible when no tab is open so the user can select their first tab")
    }
}
