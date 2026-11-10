import CraCore
import Testing

/// The toolbar's buttons (Arc 1.170/1.171). A split pane's bar follows focus and hover (GitHub #178).
struct ToolbarCompositionTests {
    typealias T = ToolbarComposition

    private func bar(_ kind: T.Kind, split: Bool = false, sidebar: Bool = false, focused: Bool = true, hovered: Bool = false,
                     back: Bool = false, forward: Bool = false, loading: Bool = false, pinned: [String] = []) -> T {
        T(kind: kind, inSplit: split, sidebarVisible: sidebar, focusedPane: focused, hovered: hovered, canGoBack: back,
          canGoForward: forward, isLoading: loading, pinnedExtensions: pinned)
    }

    /// The full bar with the sidebar hidden: the toggle first, then ← → ↻ (#50).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/50"))
    func theFullBar() {
        let full = bar(.normal, back: true, loading: true, pinned: ["a", "b"])
        // Toggle, ← → and ↻ (an ✕ while loading); pinned extensions, Extensions, Split View.
        #expect(full.left == [.toggleSidebar, .back(enabled: true), .forward(enabled: false), .reload(loading: true, enabled: true)])
        #expect(full.right == [.pinnedExtension("a"), .pinnedExtension("b"), .extensions, .addSplit])
    }

    /// With no extension installed the sliders still open the Site Control Center (Share, Boost,
    /// Capture, the site's settings), as in Arc (#226).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/226"))
    func theSlidersShowWithoutExtensions() {
        #expect(bar(.normal).right == [.extensions, .addSplit])
        #expect(bar(.normal, split: true).right == [.extensions, .splitOptions, .closePane])
    }

    /// The sidebar's URL field (toolbar hidden): pins while they fit, Copy Link, then the sliders,
    /// with or without extensions (#226).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/226"))
    func theURLFieldHasTheSlidersWithoutExtensions() {
        #expect(T.urlFieldAccessories(pinnedExtensions: [], fieldWidth: 224) == [.copyURL, .extensions])
        #expect(T.urlFieldAccessories(pinnedExtensions: ["a", "b"], fieldWidth: 224)
            == [.pinnedExtension("a"), .pinnedExtension("b"), .copyURL, .extensions])
        // Too many to leave the address its room: they go in the grid over the favorites.
        #expect(T.urlFieldAccessories(pinnedExtensions: ["a", "b", "c", "d", "e"], fieldWidth: 224) == [.copyURL, .extensions])
    }

    /// With the sidebar shown its header carries the toggle and the bar has none (#50).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/50"))
    func theShownSidebarCarriesTheToggle() {
        // Arc 1.171, #50: the sidebar's header has the toggle, the bar none.
        #expect(bar(.normal, sidebar: true).left == [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: true)])
        #expect(bar(.noTab, sidebar: true).left.first == .back(enabled: false))
        #expect(bar(.developer, sidebar: true).left.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func theFocusedPaneHasEverythingButTheToggleAndSplitView() {
        // Arc 1.171 (#178): ← → ↻ · address · pinned extensions · Extensions · options · close.
        let pane = bar(.normal, split: true, back: true, loading: true, pinned: ["a"])
        #expect(pane.left == [.back(enabled: true), .forward(enabled: false), .reload(loading: true, enabled: true)])
        #expect(pane.right == [.pinnedExtension("a"), .extensions, .splitOptions, .closePane])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func anUnfocusedPaneShowsOnlyTheEssentials() {
        // Arc's onlyShowEssentialControls: ← →, the address and close.
        let pane = bar(.normal, split: true, focused: false, back: true, pinned: ["a"])
        #expect(pane.left == [.back(enabled: true), .forward(enabled: false)])
        #expect(pane.right == [.closePane])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func hoveringAnUnfocusedPaneRevealsItsControls() {
        // Arc's onHover blueprint: the focused pane's set, so a click that focuses it moves nothing.
        let pane = bar(.normal, split: true, focused: false, hovered: true, pinned: ["a"])
        #expect(pane.left == [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: true)])
        #expect(pane.right == [.pinnedExtension("a"), .extensions, .splitOptions, .closePane])
        #expect(pane == bar(.normal, split: true, pinned: ["a"]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func hoverChangesNothingOutsideASplit() {
        let a = bar(.normal, pinned: ["a"])
        #expect(bar(.normal, hovered: true, pinned: ["a"]) == a)
        #expect(bar(.normal, focused: false, pinned: ["a"]) == a)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/178")) func anEmptyPaneHasGreyedNavigationAndClose() {
        for focused in [true, false] {
            for hovered in [true, false] {
                let pane = bar(.emptyPane, split: true, focused: focused, hovered: hovered, pinned: ["a"])
                #expect(pane.left == [.back(enabled: false), .forward(enabled: false)])
                #expect(pane.right == [.closePane])
            }
        }
    }

    @Test func noTabGreysTheNavigation() {
        let noTab = bar(.noTab, pinned: ["a"])
        #expect(noTab.left == [.toggleSidebar, .back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: false)])
        #expect(noTab.right == [.pinnedExtension("a"), .extensions, .addSplit])
    }

    /// The developer bar: Copy, a divider, then Console, Network and Inspect (#88), then Arc's
    /// Extensions Menu before the pinned extensions and Split View (Arc 1.171, AX read 8 Nov 2026).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/88"))
    func theDeveloperBar() {
        // Copy · divider · Console, Network, Inspect before the right end (Arc 1.170, #88).
        let dev = bar(.developer, pinned: ["a", "b"])
        #expect(dev.left == [.toggleSidebar])
        #expect(dev.right == [.copyURL, .divider, .console, .network, .inspect, .extensions, .pinnedExtension("a"),
                              .pinnedExtension("b"), .addSplit])
    }
}

/// Arc's translate button (#310): on a page Chromium can translate, the first of the right-hand
/// buttons, left of the sliders; not on an unfocused split pane's essentials.
struct ToolbarTranslateTests {
    typealias T = ToolbarComposition

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310"))
    func translatablePageHasTheButton() {
        let bar = T(kind: .normal, inSplit: false, sidebarVisible: true, focusedPane: true, canGoBack: false, canGoForward: false,
                    isLoading: false, pinnedExtensions: [], translatable: true)
        #expect(bar.right == [.translate, .extensions, .addSplit])
        let plain = T(kind: .normal, inSplit: false, sidebarVisible: true, focusedPane: true, canGoBack: false, canGoForward: false,
                      isLoading: false, pinnedExtensions: [])
        #expect(!plain.right.contains(.translate))
    }

    @Test func notOnAnUnfocusedPane() {
        let pane = T(kind: .normal, inSplit: true, sidebarVisible: true, focusedPane: false, canGoBack: false, canGoForward: false,
                     isLoading: false, pinnedExtensions: [], translatable: true)
        #expect(pane.right == [.closePane])
    }
}
