import CraCore
import Testing

/// Full screen with the sidebar hidden fills the screen edge to edge, as in Arc (issue #315).
struct CardFillTests {
    /// The report: in full screen with the sidebar hidden, a margin stayed around the page. Arc
    /// fills the screen there; Cra kept its windowed 10 pt inset.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/315"))
    func fullScreenWithTheSidebarHiddenFillsTheScreen() {
        #expect(CardFill.fillsWindow(edgeToEdge: false, fullScreen: true, sidebarShown: false))
    }

    /// Arc keeps the inset in full screen while the sidebar is shown, and in a window either way.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/315"))
    func theInsetStaysElsewhere() {
        #expect(!CardFill.fillsWindow(edgeToEdge: false, fullScreen: true, sidebarShown: true))
        #expect(!CardFill.fillsWindow(edgeToEdge: false, fullScreen: false, sidebarShown: false))
        #expect(!CardFill.fillsWindow(edgeToEdge: false, fullScreen: false, sidebarShown: true))
    }

    /// The edge-to-edge setting (#24) fills the window in every state.
    @Test func edgeToEdgeAlwaysFills() {
        for fullScreen in [false, true] {
            for sidebarShown in [false, true] {
                #expect(CardFill.fillsWindow(edgeToEdge: true, fullScreen: fullScreen, sidebarShown: sidebarShown))
            }
        }
    }
}
