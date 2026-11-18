import CoreGraphics
import Foundation

/// What keeps the floating sidebar out whatever the pointer does: something it opened that lies beside
/// it, past where the pointer would send it away (FloatingSidebarGeometry.shouldHide). GitHub #531: the
/// Site Control Center (236 pt, centred on the sliders near the sidebar's right edge) and an extension's
/// popup run from it; the sidebar slid away and left them on their own.
public struct FloatingSidebarKeepOut: Equatable {
    /// A folder's preview beside a row.
    public var folderPreviewOpen = false
    /// The Site Control Center, opened from the sidebar's URL field.
    public var siteControlsOpen = false
    /// The point (screen) the extension popup on screen hangs from, nil while none is.
    public var popupAnchor: CGPoint?
    /// The floating sidebar's panel (screen), nil while it has none.
    public var panelFrame: CGRect?
    /// Until when a popup the sidebar asked for is still on its way, nil when none is.
    public var popupAwaitedUntil: Date?

    /// How long the sidebar waits for a popup it asked for: as long as ExtensionActions watches for one.
    /// Chrome shows it a moment after the click, while the pointer is still over the closed menu.
    public static let popupWait: TimeInterval = 3

    public init(folderPreviewOpen: Bool = false, siteControlsOpen: Bool = false, popupAnchor: CGPoint? = nil,
                panelFrame: CGRect? = nil, popupAwaitedUntil: Date? = nil) {
        self.folderPreviewOpen = folderPreviewOpen
        self.siteControlsOpen = siteControlsOpen
        self.popupAnchor = popupAnchor
        self.panelFrame = panelFrame
        self.popupAwaitedUntil = popupAwaitedUntil
    }

    /// Whether the sidebar stays out now. Once a popup is up, where it hangs decides, not the wait: one
    /// hanging from the sidebar keeps it, one under the toolbar (an extension's shortcut) doesn't.
    public func staysOut(now: Date) -> Bool {
        if folderPreviewOpen || siteControlsOpen { return true }
        if let anchor = popupAnchor {
            return panelFrame.map { $0.insetBy(dx: -1, dy: -1).contains(anchor) } ?? false
        }
        return popupAwaitedUntil.map { now < $0 } ?? false
    }

    /// The wait is over once a popup is up: from then on `popupAwaitedUntil` can go.
    public var popupArrived: Bool { popupAnchor != nil }
}

/// Where an extension's popup run from the Site Control Center hangs (its top-right point, screen).
public enum SiteControlsPopupAnchor {
    /// Opened from the sidebar's URL field (toolbar hidden, not from a split pane's bar): under that field,
    /// right edge on the sliders, as a pin in the sidebar's grid hangs it from its own button (#531). nil:
    /// as from the toolbar, under the extension's pinned button or at the page's right end.
    public static func fromSidebar(showToolbar: Bool, openedInPaneBar: Bool, slidersFrame: CGRect?,
                                   urlFieldBottom: CGFloat?) -> CGPoint? {
        guard !showToolbar, !openedInPaneBar, let sliders = slidersFrame, let y = urlFieldBottom else { return nil }
        return CGPoint(x: sliders.maxX, y: y)
    }
}
