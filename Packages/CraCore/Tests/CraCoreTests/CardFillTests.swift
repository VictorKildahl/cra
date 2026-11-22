import CraCore
import Foundation
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

    /// Edge to edge the card is square (#24), as is Arc's full screen with the sidebar hidden (#315).
    @Test func edgeToEdgeIsSquareByDefault() {
        for fullScreen in [false, true] {
            for sidebarShown in [false, true] {
                #expect(CardFill.cornerRadius(edgeToEdge: true, roundedCorners: false, fullScreen: fullScreen,
                                              sidebarShown: sidebarShown, radius: 6) == 0)
            }
        }
        #expect(CardFill.cornerRadius(edgeToEdge: false, roundedCorners: false, fullScreen: true, sidebarShown: false, radius: 6) == 0)
    }

    /// Ideas #582: with Rounded corners, edge to edge keeps the pages' round, sidebar shown or not.
    @Test func roundedCornersKeepTheRoundEdgeToEdge() {
        for fullScreen in [false, true] {
            for sidebarShown in [false, true] {
                #expect(CardFill.cornerRadius(edgeToEdge: true, roundedCorners: true, fullScreen: fullScreen,
                                              sidebarShown: sidebarShown, radius: 6) == 6)
                // The margin stays gone: only the corners change.
                #expect(CardFill.fillsWindow(edgeToEdge: true, fullScreen: fullScreen, sidebarShown: sidebarShown))
            }
        }
    }

    /// Without edge to edge the setting changes nothing: Arc's inset card is rounded, its full-screen fill square.
    @Test func roundedCornersOnlyActsEdgeToEdge() {
        #expect(CardFill.cornerRadius(edgeToEdge: false, roundedCorners: true, fullScreen: false, sidebarShown: true, radius: 6) == 6)
        #expect(CardFill.cornerRadius(edgeToEdge: false, roundedCorners: true, fullScreen: true, sidebarShown: false, radius: 6) == 0)
    }

    @Test func roundedCornersIsOffByDefault() throws {
        #expect(!AppSettings().edgeToEdgeRoundedCorners)
        #expect(!(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))).edgeToEdgeRoundedCorners)
        #expect(UsageStats.unreportedSettings.contains("edgeToEdgeRoundedCorners"))
    }
}
