import Foundation

/// How a window presents its sidebar, worked out from what the window shows each time and never stored.
///
/// Arc holds a hidden sidebar open while the window has no tab: it stays out over the empty window,
/// and neither the pointer moving away nor another app coming to the front sends it in. The sidebar
/// button still docks it and detaches it again, and selecting a tab ends the hold. GitHub #483 (the
/// reporter's recording of Arc), and Arc observed on 17 Nov 2026. Another reason to hold the sidebar
/// out is one more fact here.
public struct SidebarPresentation: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Beside the page.
        case docked
        /// Out of sight: the window's edge brings it out over the page, and it goes when the pointer does.
        case hidden
        /// Out over the window and kept there.
        case heldOpen
    }

    public let mode: Mode
    /// Whether a floating sidebar that is out may go on its own: the pointer moving away, or another app
    /// coming to the front. The sidebar button and the window's own actions don't ask.
    public let mayRetract: Bool

    /// - Parameters:
    ///   - sidebarVisible: the window's saved choice, docked or hidden (`WindowSession.sidebarVisible`).
    ///   - hasSelectedTab: the window's focused space has a tab selected.
    ///   - folderPreviewOpen: a folder's preview is open beside the sidebar, which still belongs to it.
    ///   - pageFullscreen: a page is in element full screen (a video). The docked sidebar is out of sight
    ///     then, and the window's edge brings it out over the page (`FloatingSidebarGeometry.mayReveal`, #315).
    public init(sidebarVisible: Bool, hasSelectedTab: Bool, folderPreviewOpen: Bool = false, pageFullscreen: Bool = false) {
        // A page in full screen has a tab, so it is never the empty window held open.
        mode = pageFullscreen ? .hidden : sidebarVisible ? .docked : hasSelectedTab ? .hidden : .heldOpen
        mayRetract = mode != .heldOpen && !folderPreviewOpen
    }
}
