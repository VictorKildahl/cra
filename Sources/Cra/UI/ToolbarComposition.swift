import Foundation

/// Which buttons Arc's toolbar carries, in order, for a pane's state; PaneToolbarView makes
/// and places the views. Measured against Arc 1.170: the full bar is sidebar toggle ← → ↻ on
/// the left and pinned extensions, Extensions, Split View on the right; a split pane has only
/// ← → and its options (focused pane) and close; the developer bar swaps the navigation for
/// copy · divider · DevTools. The toggle is there only while the sidebar is hidden or floating:
/// otherwise the sidebar's header carries it (Arc 1.171, GitHub #50).
struct ToolbarComposition: Equatable {
    enum Kind: Equatable { case noTab, emptyPane, normal, developer }

    enum Item: Equatable {
        case toggleSidebar
        case back(enabled: Bool)
        case forward(enabled: Bool)
        /// An ✕ while the page loads.
        case reload(loading: Bool, enabled: Bool)
        case copyURL
        case divider
        case devTools
        case pinnedExtension(String)
        case extensions
        case addSplit
        case splitOptions
        case closePane
    }

    var left: [Item] = []
    var right: [Item] = []

    init(kind: Kind, inSplit: Bool, sidebarVisible: Bool, focusedPane: Bool, canGoBack: Bool, canGoForward: Bool, isLoading: Bool,
         pinnedExtensions: [String], hasExtensions: Bool) {
        // Never in a split pane (Arc 1.170: only ← → in a pane) or an empty one.
        if !inSplit, !sidebarVisible, kind != .emptyPane { left.append(.toggleSidebar) }
        switch kind {
        case .noTab:
            left += [.back(enabled: false), .forward(enabled: false), .reload(loading: false, enabled: false)]
        case .emptyPane:
            left = [.back(enabled: false), .forward(enabled: false)]
        case .normal:
            // Split panes drop refresh too.
            left += [.back(enabled: canGoBack), .forward(enabled: canGoForward)]
            if !inSplit { left.append(.reload(loading: isLoading, enabled: true)) }
        case .developer:
            right += [.copyURL, .divider, .devTools]
        }
        // Arc's right end: pinned extensions, the Extensions button, then Split View; also on
        // the no-tab bar. A split pane has its options (focused pane only) and close instead.
        if !inSplit, kind != .emptyPane {
            right += pinnedExtensions.map(Item.pinnedExtension)
            if hasExtensions { right.append(.extensions) }
            right.append(.addSplit)
        }
        if inSplit {
            if focusedPane, kind != .emptyPane { right.append(.splitOptions) }
            right.append(.closePane)
        }
    }
}
