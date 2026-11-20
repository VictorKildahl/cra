import CraCore
import Foundation
import Testing

/// A Peek's address in the sidebar, as in Arc (GitHub #648).
struct PeekAddressTests {
    static let page = PeekAddress.Page(id: UUID(), url: "https://www.iana.org/help/example-domains", canGoBack: true,
                                       canGoForward: false, isLoading: false)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/648"))
    func addressInTheSidebarLeavesTheCardWithoutABar() {
        // Arc 1.174: the address in the sidebar, the card's page under no bar of its own.
        #expect(!PeekAddress.cardHasBar(showToolbar: false, autoHidePeekToolbar: false, easel: false))
        // Arc 1.171 with its toolbar: the card's 32 pt bar.
        #expect(PeekAddress.cardHasBar(showToolbar: true, autoHidePeekToolbar: false, easel: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/648"))
    func theHideUntilNeededSwitchKeepsItsBar() {
        // #493's switch is a bar that slides in at the card's top: it stays, whichever way the address is placed.
        #expect(PeekAddress.cardHasBar(showToolbar: false, autoHidePeekToolbar: true, easel: false))
        #expect(PeekAddress.cardHasBar(showToolbar: true, autoHidePeekToolbar: true, easel: false))
    }

    @Test func anEaselInPeekNeverHasABar() {
        for toolbar in [false, true] {
            for autoHide in [false, true] {
                #expect(!PeekAddress.cardHasBar(showToolbar: toolbar, autoHidePeekToolbar: autoHide, easel: true))
            }
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/648"))
    func theSidebarFieldFollowsThePeekOnlyWhileItHasTheAddress() {
        #expect(PeekAddress.sidebarShows(peek: Self.page, showToolbar: false) == Self.page)
        // The toolbar has the address: the sidebar has no field, and the toolbar's is the tab's.
        #expect(PeekAddress.sidebarShows(peek: Self.page, showToolbar: true) == nil)
        // No Peek in front (closed, or waiting behind another tab): the tab's address.
        #expect(PeekAddress.sidebarShows(peek: nil, showToolbar: false) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/648"))
    func aPeekInTheFieldOffersOnlyCopyLink() {
        let all = ToolbarComposition.urlFieldAccessories(pinnedExtensions: ["ublock"], fieldWidth: 300)
        #expect(all.contains(.extensions) && all.contains(.pinnedExtension("ublock")))
        #expect(PeekAddress.fieldAccessories(all) == [.copyURL])
    }
}
