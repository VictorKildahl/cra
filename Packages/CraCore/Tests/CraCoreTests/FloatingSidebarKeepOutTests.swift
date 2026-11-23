import CoreGraphics
import CraCore
import Foundation
import Testing

/// GitHub #531: with the sidebar and the toolbar hidden, the floating sidebar keeps what it opened.
@Suite struct FloatingSidebarKeepOutTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1000)
    /// A floating sidebar's panel: window at x 100, sidebar 264 pt wide plus its 5 pt margin.
    private let panel = CGRect(x: 100, y: 100, width: 269, height: 700)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func nothingOpenLetsThePointerDecide() {
        #expect(!FloatingSidebarKeepOut().staysOut(now: now))
        #expect(!FloatingSidebarKeepOut(panelFrame: panel).staysOut(now: now))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func folderPreviewAndSiteControlsKeepIt() {
        #expect(FloatingSidebarKeepOut(folderPreviewOpen: true).staysOut(now: now))
        // The menu lies past the sidebar's leave line: it used to slide away under it.
        #expect(FloatingSidebarKeepOut(siteControlsOpen: true).staysOut(now: now))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func waitsForThePopupItAskedFor() {
        let awaited = FloatingSidebarKeepOut(panelFrame: panel, popupAwaitedUntil: now.addingTimeInterval(FloatingSidebarKeepOut.popupWait))
        #expect(awaited.staysOut(now: now))
        #expect(awaited.staysOut(now: now.addingTimeInterval(2.9)))
        // No popup came (an action without one, onClicked): the pointer decides again.
        #expect(!awaited.staysOut(now: now.addingTimeInterval(3)))
        #expect(!awaited.popupArrived)
        #expect(FloatingSidebarKeepOut.popupWait == 3)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func aPopupHangingFromItKeepsIt() {
        // Under the URL field, right edge on the sliders (x 100 + 264 − 10).
        let fromSidebar = FloatingSidebarKeepOut(popupAnchor: CGPoint(x: 354, y: 740), panelFrame: panel)
        #expect(fromSidebar.staysOut(now: now))
        #expect(fromSidebar.popupArrived)
        // Long after the wait: the popup itself keeps the sidebar, for as long as it is up.
        #expect(fromSidebar.staysOut(now: now.addingTimeInterval(600)))
        // On the panel's edge (1 pt of slack for rounding).
        #expect(FloatingSidebarKeepOut(popupAnchor: CGPoint(x: panel.maxX + 0.5, y: 740), panelFrame: panel).staysOut(now: now))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func aPopupElsewhereDoesNot() {
        // Under the toolbar at the page's right end (an extension's shortcut): the pointer decides.
        let elsewhere = FloatingSidebarKeepOut(popupAnchor: CGPoint(x: 1200, y: 740), panelFrame: panel)
        #expect(!elsewhere.staysOut(now: now))
        // Once it is up, where it hangs decides, even while the wait would still run.
        var arrived = elsewhere
        arrived.popupAwaitedUntil = now.addingTimeInterval(2)
        #expect(!arrived.staysOut(now: now))
        // No panel to hang from.
        #expect(!FloatingSidebarKeepOut(popupAnchor: CGPoint(x: 354, y: 740)).staysOut(now: now))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/531")) func popupFromTheSidebarHangsUnderItsURLField() {
        let sliders = CGRect(x: 326, y: 748, width: 28, height: 28)
        // Toolbar hidden: under the URL field, right edge on the sliders. It hung at the page's top right.
        #expect(SiteControlsPopupAnchor.fromSidebar(showToolbar: false, openedInPaneBar: false, slidersFrame: sliders,
                                                    urlFieldBottom: 742) == CGPoint(x: 354, y: 742))
        // The toolbar has the sliders: as before, under the toolbar.
        #expect(SiteControlsPopupAnchor.fromSidebar(showToolbar: true, openedInPaneBar: false, slidersFrame: sliders,
                                                    urlFieldBottom: 742) == nil)
        // A split pane's bar has its own sliders with the toolbar hidden: under that bar.
        #expect(SiteControlsPopupAnchor.fromSidebar(showToolbar: false, openedInPaneBar: true, slidersFrame: sliders,
                                                    urlFieldBottom: 742) == nil)
        // No URL field to hang from.
        #expect(SiteControlsPopupAnchor.fromSidebar(showToolbar: false, openedInPaneBar: false, slidersFrame: nil,
                                                    urlFieldBottom: 742) == nil)
        #expect(SiteControlsPopupAnchor.fromSidebar(showToolbar: false, openedInPaneBar: false, slidersFrame: sliders,
                                                    urlFieldBottom: nil) == nil)
    }

    /// Opened with no button under the pointer (VoiceOver's press, Nightly's scripted press with the pointer in a
    /// corner): it hung at the pointer's x, off the window, and macOS showed nothing.
    @Test func popupWithNoButtonUnderThePointerHangsFromTheSliders() {
        let sliders = CGRect(x: 300, y: 748, width: 32, height: 28)
        #expect(SiteControlsPopupAnchor.buttonMidX(given: nil, underPointer: nil, sliders: sliders, pointerX: 0) == 316)
        // A button that was pressed, or is under the pointer, wins.
        let pressed = CGRect(x: 900, y: 760, width: 32, height: 28)
        #expect(SiteControlsPopupAnchor.buttonMidX(given: pressed, underPointer: nil, sliders: sliders, pointerX: 0) == 916)
        #expect(SiteControlsPopupAnchor.buttonMidX(given: nil, underPointer: pressed, sliders: sliders, pointerX: 0) == 916)
        // Nothing to hang from: the pointer, as before.
        #expect(SiteControlsPopupAnchor.buttonMidX(given: nil, underPointer: nil, sliders: nil, pointerX: 40) == 40)
    }

    /// GitHub #691: Arc 1.174.1 keeps the floating sidebar out for as long as its address panel is
    /// open, the pointer far into the page included; the in-place field (#692, Cra's option) as well,
    /// so typing never goes into a sidebar that slid away.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/691")) func theAddressBeingEditedKeepsIt() {
        #expect(FloatingSidebarKeepOut(addressOpen: true, panelFrame: panel).staysOut(now: now))
        #expect(!FloatingSidebarKeepOut(addressOpen: false, panelFrame: panel).staysOut(now: now))
    }
}
