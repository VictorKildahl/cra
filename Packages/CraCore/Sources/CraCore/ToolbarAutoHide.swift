import CoreGraphics
import Foundation

/// Settings ▸ Tabs ▸ "Hide the toolbar until the pointer reaches the top of the page" (not in Arc;
/// Zen's compact mode for its toolbar). The toolbar stops taking room above the page: it floats
/// over the page's top edge, out of sight until the pointer comes to the top of the card, and goes
/// again once the pointer has left it.
///
/// Points are in AppKit's coordinates (y grows upward), so a card's top edge is its `maxY`.
public enum ToolbarAutoHide {
    /// How far into the page's top the strip that brings the toolbar out reaches. The margin above
    /// the card counts as well, so only an edge-to-edge page has to be hit this precisely.
    public static let revealInside: CGFloat = 6
    /// How far above the window the strip reaches, for a pointer thrown past the top edge.
    public static let revealOutside: CGFloat = 4
    /// How far under the toolbar the pointer may drift before the toolbar is let go.
    public static let leaveSlack: CGFloat = 16
    /// How long the pointer rests in the strip before the toolbar comes out: a pointer on its way
    /// to the top of a page, or passing over the edge, brings nothing out.
    public static let revealDwell: TimeInterval = 0.1
    /// How long after the pointer left before the toolbar goes, so a hand that slips off the bar
    /// and comes back keeps it.
    public static let hideDelay: TimeInterval = 0.35
    public static let revealDuration: TimeInterval = 0.16
    public static let hideDuration: TimeInterval = 0.12

    /// Whether the toolbar floats over the page instead of sitting above it. Only the toolbar of a
    /// page shown alone does: a split's panes keep their bars, since those say which pane is which,
    /// and so does the developer bar, which is there to be seen. With DevTools open the page is in
    /// a window of its own that nothing of Cra's can float over, so the toolbar sits above it again.
    public static func floats(enabled: Bool, toolbarShown: Bool, panes: Int, developerBar: Bool, devToolsOpen: Bool,
                              pageFullscreen: Bool) -> Bool {
        enabled && toolbarShown && panes == 1 && !developerBar && !devToolsOpen && !pageFullscreen
    }

    /// The strip that brings the toolbar out: the top of the card and everything above it, up to
    /// just outside the window (`container` is the view the card sits in).
    public static func inRevealStrip(_ point: CGPoint, card: CGRect, container: CGRect) -> Bool {
        point.x >= card.minX && point.x <= card.maxX
            && point.y >= card.maxY - revealInside && point.y <= container.maxY + revealOutside
    }

    /// Where the pointer keeps a toolbar that is out: on the bar, a little under it, and above it.
    public static func inKeepZone(_ point: CGPoint, card: CGRect, container: CGRect, barHeight: CGFloat) -> Bool {
        point.x >= card.minX && point.x <= card.maxX
            && point.y >= card.maxY - barHeight - leaveSlack && point.y <= container.maxY + revealOutside
    }

    /// How far from the bar's bottom edge the top of something that hangs from it may be: Cra's
    /// popovers overlap the bar by 4 pt, and a popup's shadow or arrow shifts its frame a little.
    public static let hangTolerance: CGFloat = 14

    /// Whether a window of Cra's (its frame, on screen) hangs from the bar of that card: its top
    /// edge is at the bar's bottom and it is narrower than the card. The page's own window and the
    /// overlay panel cover the card and start elsewhere, so they don't count.
    public static func hangsFromBar(_ frame: CGRect, card: CGRect, barHeight: CGFloat) -> Bool {
        let barBottom = card.maxY - barHeight
        return abs(frame.maxY - barBottom) <= hangTolerance && frame.width < card.width - 40
            && frame.maxX > card.minX && frame.minX < card.maxX
    }

    /// Where a pointer sample is, for the tracker.
    public enum Pointer: Equatable, Sendable {
        /// In the strip at the top of the card.
        case strip
        /// On the toolbar or close enough to keep it.
        case bar
        /// Over the page, or anywhere else in the window that isn't the toolbar's.
        case away
        /// Over something that hangs from the window (a popover, a menu): no telling, so nothing changes.
        case elsewhere
    }

    public static func classify(_ point: CGPoint, card: CGRect, container: CGRect, barHeight: CGFloat, shown: Bool) -> Pointer {
        if inRevealStrip(point, card: card, container: container) { return .strip }
        if shown, inKeepZone(point, card: card, container: container, barHeight: barHeight) { return .bar }
        return .away
    }
}

/// Whether the floating toolbar is out, from pointer samples and the clock.
///
/// The pointer has to rest in the strip for `revealDwell` before the toolbar comes out, and has to
/// be away for `hideDelay` before it goes. A resting pointer sends no samples, so each sample
/// returns when to look again; `tick(at:)` is that look.
public struct ToolbarAutoHideTracker: Equatable, Sendable {
    public private(set) var shown = false
    private var last: ToolbarAutoHide.Pointer = .away
    private var held = false
    private var stripSince: TimeInterval?
    private var awaySince: TimeInterval?

    public init() {}

    /// One pointer sample. `held` keeps a toolbar that is out where it is: a mouse button is down
    /// (a drag that began on the bar, a menu being pulled), or something hangs under the bar.
    /// Returns the time to call `tick(at:)`, when the state may change without the pointer moving.
    @discardableResult
    public mutating func sample(_ pointer: ToolbarAutoHide.Pointer, held: Bool = false, at now: TimeInterval) -> TimeInterval? {
        last = pointer
        self.held = held
        return step(at: now)
    }

    /// The same sample again, later.
    @discardableResult
    public mutating func tick(held: Bool? = nil, at now: TimeInterval) -> TimeInterval? {
        if let held { self.held = held }
        return step(at: now)
    }

    /// Out now, whatever the pointer does: something asked for the toolbar (a popover hangs under
    /// one of its buttons). It goes again the usual way once the pointer is away and nothing holds it.
    public mutating func bringOut() {
        shown = true
        stripSince = nil
        awaySince = nil
    }

    /// Hidden now: the toolbar stopped floating, or another tab took the card.
    public mutating func reset() {
        self = ToolbarAutoHideTracker()
    }

    private mutating func step(at now: TimeInterval) -> TimeInterval? {
        if shown {
            stripSince = nil
            guard last == .away, !held else { awaySince = nil; return nil }
            let start = awaySince ?? now
            awaySince = start
            // Compared with the time handed back, so the look asked for is never a hair too early.
            let due = start + ToolbarAutoHide.hideDelay
            guard now >= due else { return due }
            shown = false
            awaySince = nil
            return nil
        }
        awaySince = nil
        guard last == .strip else { stripSince = nil; return nil }
        let start = stripSince ?? now
        stripSince = start
        let due = start + ToolbarAutoHide.revealDwell
        guard now >= due else { return due }
        shown = true
        stripSince = nil
        return nil
    }
}

extension AppSettings {
    /// Whether a page shown alone has its toolbar floating over it (`autoHideToolbar`). The
    /// developer bar on a Developer Mode site stays where it is; the shell adds the rules that
    /// need the window (a split, DevTools, a page in full screen).
    public func hidesToolbar(above url: String?) -> Bool {
        autoHideToolbar && showToolbar && url.map(isDeveloperMode) != true
    }
}
