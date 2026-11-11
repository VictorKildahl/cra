import CoreGraphics
import Foundation

/// Which buttons Arc's toolbar carries, in order, for a pane's state; PaneToolbarView makes
/// and places the views. Measured against Arc 1.170: the full bar is sidebar toggle ← → ↻ on
/// the left and pinned extensions, Extensions, Split View on the right; the developer bar swaps
/// the navigation for copy · divider · Console, Network, Inspect (Arc's Toggle Console, Toggle
/// Network Panel and Inspect Element, GitHub #88; Arc's Capture Window and Capture between them
/// are not in Cra). The toggle is there only while the sidebar is hidden or floating: otherwise
/// the sidebar's header carries it (Arc 1.171, GitHub #50).
///
/// A split pane's bar (Arc 1.171, GitHub #178) has no toggle and no Split View button. The
/// focused pane carries ← → ↻, the address, the pinned extensions, Extensions, the split options
/// and close; the other panes show only Arc's essential controls (`onlyShowEssentialControls`:
/// ← →, the address and close) until the pointer is over their bar (Arc's `onHover` toolbar
/// blueprint), which reveals the rest.
///
/// The Extensions button (Arc's sliders) opens the Site Control Center: Share, Boost, Capture,
/// the extensions with their "+" and the site's settings. It is there with no extension
/// installed too, in the toolbar and in the sidebar's URL field (GitHub #226).
public struct ToolbarComposition: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case noTab, emptyPane, normal, developer }

    public enum Item: Equatable, Sendable {
        case toggleSidebar
        case back(enabled: Bool)
        case forward(enabled: Bool)
        /// An ✕ while the page loads.
        case reload(loading: Bool, enabled: Bool)
        case copyURL
        case divider
        case console
        case network
        case inspect
        case pinnedExtension(String)
        /// Pop-ups Chromium blocked on the page (BlockedPopups): Chrome's address-bar icon,
        /// before the translate button.
        case blockedPopups
        /// Arc's translate button (`character.bubble`, "Translation Options"), while Chromium
        /// can translate the page or it is translated (GitHub #310).
        case translate
        case extensions
        case addSplit
        case splitOptions
        case closePane
    }

    public var left: [Item] = []
    public var right: [Item] = []

    /// `hovered`: the pointer is over this bar, which reveals an unfocused pane's controls.
    /// `translatable`: the page offers translation (PageTranslation.offersTranslation).
    /// `blockedPopups`: Chromium holds back pop-ups the page opened (BlockedPopups.waiting).
    public init(kind: Kind, inSplit: Bool, sidebarVisible: Bool, focusedPane: Bool, hovered: Bool = false, canGoBack: Bool,
                canGoForward: Bool, isLoading: Bool, pinnedExtensions: [String], translatable: Bool = false,
                blockedPopups: Bool = false) {
        // Arc's essential controls only: a split pane that neither has the focus nor the pointer.
        let essentialOnly = inSplit && !focusedPane && !hovered
        // Never in a split pane or an empty one.
        if !inSplit, !sidebarVisible, kind != .emptyPane { left.append(.toggleSidebar) }
        switch kind {
        case .noTab:
            left += [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: false)]
        case .emptyPane:
            left = [.back(enabled: false), .forward(enabled: false)]
        case .normal:
            left += [.back(enabled: canGoBack), .forward(enabled: canGoForward)]
            if !essentialOnly { left.append(.reload(loading: isLoading, enabled: true)) }
        case .developer:
            right += [.copyURL, .divider, .console, .network, .inspect]
        }
        // Arc's right end: pinned extensions, the Extensions button, then Split View (not in a
        // split); also on the no-tab bar. The developer bar has the Extensions button first.
        if !essentialOnly, kind != .emptyPane {
            if blockedPopups, kind == .normal || kind == .developer { right.append(.blockedPopups) }
            // Arc 1.172: the translate button sits right before the sliders, 36 pt apart (#310).
            if translatable, kind == .normal || kind == .developer { right.append(.translate) }
            let pins = pinnedExtensions.map(Item.pinnedExtension)
            right += kind == .developer ? [.extensions] + pins : pins + [.extensions]
            if !inSplit { right.append(.addSplit) }
        }
        if inSplit {
            // On a hovered pane too: its bar then doesn't move when a click on it takes the focus.
            if !essentialOnly, kind != .emptyPane { right.append(.splitOptions) }
            right.append(.closePane)
        }
    }

    /// The sidebar's URL field while the toolbar is hidden, shown on hover over the header: the
    /// pinned extensions while they leave the address its room (else they go in the grid over the
    /// favorites), Copy Link, then the Site Control Center's sliders (Arc 1.171, GitHub #226).
    public static func urlFieldAccessories(pinnedExtensions: [String], fieldWidth: CGFloat) -> [Item] {
        let pins = PinnedExtensionGrid.fitsInURLField(count: pinnedExtensions.count, fieldWidth: fieldWidth) ? pinnedExtensions : []
        return pins.map(Item.pinnedExtension) + [.copyURL, .extensions]
    }
}
