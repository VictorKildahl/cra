import CoreGraphics
import CraCore
import Foundation
import Testing

/// Settings ▸ Sidebar on the right (GitHub #464, not in Arc): the window's layout in a mirror. The
/// sidebar, its resize edge, the hidden sidebar's reveal strip and the room past the window swap
/// sides; the Peek, a split drop and the toolbar's toggle keep to the page's side of the sidebar.
struct SidebarSideTests {
    /// The shell's bounds, away from zero so the mirror's centre line is not the origin's.
    let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)

    // MARK: The mirror

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func theLeftSideLeavesFramesWhereTheyAre() {
        let sidebar = CGRect(x: 20, y: 10, width: 264, height: 880)
        #expect(SidebarSide.left.place(sidebar, in: bounds) == sidebar)
        #expect(SidebarSide.left.place(CGPoint(x: 30, y: 40), in: bounds) == CGPoint(x: 30, y: 40))
        #expect(SidebarSide.left.place(dx: 12) == 12)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func theRightSideMirrorsAcrossTheMiddle() {
        // The sidebar against the left edge lands against the right one, its width kept.
        let sidebar = SidebarSide.right.place(CGRect(x: 20, y: 10, width: 264, height: 880), in: bounds)
        #expect(sidebar == CGRect(x: 1420 - 264, y: 10, width: 264, height: 880))
        // The page right of it, 10 pt in from the window's other edge, ends up left of it.
        let page = SidebarSide.right.place(CGRect(x: 284, y: 20, width: 1126, height: 860), in: bounds)
        #expect(page == CGRect(x: 30, y: 20, width: 1126, height: 860))
        #expect(page.maxX == sidebar.minX)
        // A frame hidden past the left edge is hidden past the right one.
        #expect(SidebarSide.right.place(CGRect(x: -264, y: 10, width: 264, height: 880), in: bounds).minX == bounds.maxX + 20)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func pointsMirrorBothWays() {
        let p = CGPoint(x: 25, y: 300)
        #expect(SidebarSide.right.place(p, in: bounds) == CGPoint(x: 1415, y: 300))
        #expect(SidebarSide.right.place(SidebarSide.right.place(p, in: bounds), in: bounds) == p)
        // A drag toward the window's left makes a right-hand sidebar wider.
        #expect(SidebarSide.right.place(dx: -40) == 40)
    }

    /// Folder and pinned-tab previews open beside the sidebar over the page, and a favorite's card
    /// overlaps its tile by Arc's 4 pt, on the page's side.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func cardsOpenOnThePagesSide() {
        let sidebar = CGRect(x: 1136, y: 0, width: 264, height: 880)
        #expect(SidebarSide.left.cardMinX(beside: CGRect(x: 0, y: 0, width: 264, height: 880), gap: 8, width: 300) == 272)
        #expect(SidebarSide.right.cardMinX(beside: sidebar, gap: 8, width: 300) == sidebar.minX - 8 - 300)
        let tile = CGRect(x: 1150, y: 800, width: 60, height: 50)
        #expect(SidebarSide.left.cardMinX(beside: tile, gap: -4, width: 280) == 1206)
        #expect(SidebarSide.right.cardMinX(beside: tile, gap: -4, width: 280) + 280 == 1154)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func theToggleShowsTheSidebarsSide() {
        #expect(SidebarSide.left.toggleSymbol == "sidebar.left")
        #expect(SidebarSide.right.toggleSymbol == "sidebar.right")
    }

    // MARK: The setting

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func arcsLeftIsTheDefaultAndOlderFilesKeepIt() throws {
        func decode(_ json: String) throws -> AppSettings { try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
        #expect(AppSettings().sidebarSide == .left)
        #expect(try decode("{}").sidebarSide == .left)
        #expect(try decode(#"{"sidebarSide": "right"}"#).sidebarSide == .right)
        // A value a later Cra might write doesn't reset the file.
        #expect(try decode(#"{"sidebarSide": "top", "edgeToEdgeContent": true}"#).sidebarSide == .left)
        #expect(try decode(#"{"sidebarSide": "top", "edgeToEdgeContent": true}"#).edgeToEdgeContent)
        var settings = AppSettings()
        settings.sidebarSide = .right
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).sidebarSide == .right)
    }

    /// A feature Arc never had adds nothing to the opt-in report (CONTRIBUTING.md).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func theSideIsNeverReported() {
        var settings = AppSettings()
        settings.sidebarSide = .right
        #expect(UsageStats.unreportedSettings.contains("sidebarSide"))
        #expect(UsageStats.changedSettings(settings)["sidebarSide"] == nil)
    }

    // MARK: The hidden sidebar

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464"), arguments: [(1420.0, true), (1410.0, true), (1409.9, false), (1424.0, true), (1424.1, false), (25.0, false)])
    func theRevealStripIsAtTheRightEdge(x: Double, reveals: Bool) {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: x, y: 100), in: bounds, side: .right) == reveals)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func edgeToEdgeTheRightStripIsFivePoints() {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 1415, y: 100), in: bounds, edgeToEdge: true, side: .right))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 1414.9, y: 100), in: bounds, edgeToEdge: true, side: .right))
    }

    /// Thrown past the right edge, the pointer brings it out there (#350's zone, mirrored).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464"), arguments: [(1424.1, 100.0, true), (1500.0, 100.0, true), (1676.0, 100.0, true), (1676.1, 100.0, false),
                      (-80.0, 100.0, false), (1500.0, 9.9, false)])
    func besideTheRightEdgeIsOffTheEdge(x: Double, y: Double, off: Bool) {
        #expect(FloatingSidebarGeometry.isOffLeftEdge(CGPoint(x: x, y: y), in: bounds, sidebarWidth: 264, side: .right) == off)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func itLeavesOncePastTheSidebarFromTheRight() {
        func hides(_ x: CGFloat) -> Bool {
            FloatingSidebarGeometry.shouldHide(at: CGPoint(x: x, y: 400), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0, side: .right)
        }
        // The sidebar ends 264 + 5 pt in from the right edge; the pointer may go 76 pt further.
        let edge = bounds.maxX - 264 - FloatingSidebarGeometry.margin - FloatingSidebarGeometry.leaveSlack
        #expect(!hides(edge))
        #expect(hides(edge - 1))
        #expect(!hides(1300))
        // Beside the window on its side it stays; beside the other side it goes.
        #expect(!hides(1500))
        #expect(hides(-80))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func aPointerThrownPastTheRightEdgeRevealsAfterItRests() {
        var off = FloatingSidebarOffEdge()
        #expect(off.sample(CGPoint(x: 1300, y: 400), in: bounds, sidebarWidth: 264, side: .right, at: 0) == .away)
        #expect(off.sample(CGPoint(x: 1500, y: 400), in: bounds, sidebarWidth: 264, side: .right, at: 0.03) == .waiting)
        #expect(off.sample(CGPoint(x: 1500, y: 400), in: bounds, sidebarWidth: 264, side: .right, at: 0.2) == .reveal)
        // Past the left edge brings nothing out of a right-hand sidebar.
        var left = FloatingSidebarOffEdge()
        _ = left.sample(CGPoint(x: 100, y: 400), in: bounds, sidebarWidth: 264, side: .right, at: 0)
        #expect(left.sample(CGPoint(x: -80, y: 400), in: bounds, sidebarWidth: 264, side: .right, at: 0.2) == .away)
    }

    // MARK: Beside the sidebar

    /// A Peek is centred on the page area left of the sidebar, and only that area closes it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func aPeekKeepsToThePageLeftOfTheSidebar() {
        let area = PeekLayout.area(window: CGSize(width: 1400, height: 880), contentMinX: 0, contentMaxX: 1136)
        #expect(area == CGRect(x: 0, y: 0, width: 1136, height: 880))
        let window = CGRect(x: 100, y: 50, width: 1400, height: 880)
        let dismiss = PeekLayout.dismissArea(covering: window, contentMaxX: 1136)
        #expect(dismiss.minX == 100 + PeekLayout.dismissInset)
        #expect(dismiss.maxX == window.minX + 1136)
        // Without a sidebar edge both are the whole window, as before.
        #expect(PeekLayout.dismissArea(covering: window, contentMaxX: nil) == PeekLayout.dismissArea(covering: window))
    }

    /// Next to a right-hand sidebar the drag is still the sidebar's, as Arc's 40 pt band is on the left.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func aSplitDropLeavesTheBandBesideARightHandSidebar() {
        let a = UUID()
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        func propose(_ x: CGFloat, docked: Bool = true) -> SplitDropProposal.Target? {
            SplitDropProposal.propose(at: CGPoint(x: x, y: 300), ids: [a], frames: [a: area], orientation: .horizontal, area: area,
                                      region: nil, current: nil, sidebarSide: docked, sidebarOn: .right)
        }
        #expect(propose(980) == nil)
        #expect(propose(955) == .insert(.init(index: 1, orientation: .horizontal)))
        #expect(propose(980, docked: false) == .insert(.init(index: 1, orientation: .horizontal)))
        // The left edge is free again: no sidebar there.
        #expect(propose(20) == .insert(.init(index: 0, orientation: .horizontal)))
    }

    /// With the sidebar hidden the toolbar's toggle ends the bar, on the side the sidebar comes from.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/464")) func theToolbarToggleEndsTheBar() {
        let bar = ToolbarComposition(kind: .normal, inSplit: false, sidebarVisible: false, sidebarSide: .right, focusedPane: true,
                                     canGoBack: true, canGoForward: false, isLoading: false, pinnedExtensions: ["x"])
        #expect(bar.left == [.back(enabled: true), .forward(enabled: false), .reload(loading: false, enabled: true)])
        #expect(bar.right == [.pinnedExtension("x"), .extensions, .addSplit, .toggleSidebar])
        // Shown, the sidebar's header carries it, as on the left.
        let shown = ToolbarComposition(kind: .normal, inSplit: false, sidebarVisible: true, sidebarSide: .right, focusedPane: true,
                                       canGoBack: false, canGoForward: false, isLoading: false, pinnedExtensions: [])
        #expect(!shown.left.contains(.toggleSidebar) && !shown.right.contains(.toggleSidebar))
        let split = ToolbarComposition(kind: .normal, inSplit: true, sidebarVisible: false, sidebarSide: .right, focusedPane: true,
                                       canGoBack: false, canGoForward: false, isLoading: false, pinnedExtensions: [])
        #expect(!split.right.contains(.toggleSidebar))
    }
}
