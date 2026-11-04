import CraCore
import Testing

/// The toolbar's buttons (Arc 1.170/1.171). A split pane's bar follows focus and hover (GitHub #178).
struct ToolbarCompositionTests {
    typealias T = ToolbarComposition

    private func bar(_ kind: T.Kind, split: Bool = false, sidebar: Bool = false, focused: Bool = true, hovered: Bool = false,
                     back: Bool = false, forward: Bool = false, loading: Bool = false, pinned: [String] = [],
                     extensions: Bool = false) -> T {
        T(kind: kind, inSplit: split, sidebarVisible: sidebar, focusedPane: focused, hovered: hovered, canGoBack: back,
          canGoForward: forward, isLoading: loading, pinnedExtensions: pinned, hasExtensions: extensions)
    }

    @Test func theFullBar() {
        let full = bar(.normal, back: true, loading: true, pinned: ["a", "b"], extensions: true)
        // Toggle, ← → and ↻ (an ✕ while loading); pinned extensions, Extensions, Split View.
        #expect(full.left == [.toggleSidebar, .back(enabled: true), .forward(enabled: false), .reload(loading: true, enabled: true)])
        #expect(full.right == [.pinnedExtension("a"), .pinnedExtension("b"), .extensions, .addSplit])
    }

    @Test func noExtensionsButtonWithoutExtensions() {
        #expect(bar(.normal).right == [.addSplit])
    }

    @Test func theShownSidebarCarriesTheToggle() {
        // Arc 1.171, #50: the sidebar's header has the toggle, the bar none.
        #expect(bar(.normal, sidebar: true).left == [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: true)])
        #expect(bar(.noTab, sidebar: true).left.first == .back(enabled: false))
        #expect(bar(.developer, sidebar: true).left.isEmpty)
    }

    @Test func theFocusedPaneHasEverythingButTheToggleAndSplitView() {
        // Arc 1.171 (#178): ← → ↻ · address · pinned extensions · Extensions · options · close.
        let pane = bar(.normal, split: true, back: true, loading: true, pinned: ["a"], extensions: true)
        #expect(pane.left == [.back(enabled: true), .forward(enabled: false), .reload(loading: true, enabled: true)])
        #expect(pane.right == [.pinnedExtension("a"), .extensions, .splitOptions, .closePane])
    }

    @Test func anUnfocusedPaneShowsOnlyTheEssentials() {
        // Arc's onlyShowEssentialControls: ← →, the address and close.
        let pane = bar(.normal, split: true, focused: false, back: true, pinned: ["a"], extensions: true)
        #expect(pane.left == [.back(enabled: true), .forward(enabled: false)])
        #expect(pane.right == [.closePane])
    }

    @Test func hoveringAnUnfocusedPaneRevealsItsControls() {
        // Arc's onHover blueprint: the focused pane's set, so a click that focuses it moves nothing.
        let pane = bar(.normal, split: true, focused: false, hovered: true, pinned: ["a"], extensions: true)
        #expect(pane.left == [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: true)])
        #expect(pane.right == [.pinnedExtension("a"), .extensions, .splitOptions, .closePane])
        #expect(pane == bar(.normal, split: true, pinned: ["a"], extensions: true))
    }

    @Test func hoverChangesNothingOutsideASplit() {
        let a = bar(.normal, pinned: ["a"], extensions: true)
        #expect(bar(.normal, hovered: true, pinned: ["a"], extensions: true) == a)
        #expect(bar(.normal, focused: false, pinned: ["a"], extensions: true) == a)
    }

    @Test func anEmptyPaneHasGreyedNavigationAndClose() {
        for focused in [true, false] {
            for hovered in [true, false] {
                let pane = bar(.emptyPane, split: true, focused: focused, hovered: hovered, pinned: ["a"], extensions: true)
                #expect(pane.left == [.back(enabled: false), .forward(enabled: false)])
                #expect(pane.right == [.closePane])
            }
        }
    }

    @Test func noTabGreysTheNavigation() {
        let noTab = bar(.noTab, pinned: ["a"], extensions: true)
        #expect(noTab.left == [.toggleSidebar, .back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: false)])
        #expect(noTab.right == [.pinnedExtension("a"), .extensions, .addSplit])
    }

    @Test func theDeveloperBar() {
        // Copy · divider · Console, Network, Inspect before the right end (Arc 1.170, #88).
        let dev = bar(.developer, pinned: ["a"])
        #expect(dev.left == [.toggleSidebar])
        #expect(dev.right == [.copyURL, .divider, .console, .network, .inspect, .pinnedExtension("a"), .addSplit])
    }
}
