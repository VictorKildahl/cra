import Foundation

/// Arc's Settings ▸ Advanced "Allow window dragging from the top of webpages" (on by default). Arc 1.172.2,
/// measured with real drags on 11 Nov 2026 (#363): a drag that starts within 60 pt of the pane card's top,
/// its bar included, moves the window. With the toolbar hidden that is the top 60 pt of the page (59 moved,
/// 60 didn't); under the 32 pt toolbar it is the top 28 pt (27 moved, 28 didn't). Arc's WindowContentGrabber
/// only takes drags with the ordinary arrow cursor; the page receives the press immediately, the first drag
/// event starts the window drag, and the page gets the release.
public enum PageTopDrag {
    /// How far down from the card's top the band reaches, the bar included (Arc's controller: `60 − y`, y the
    /// bar's bottom edge).
    public static let reach: Double = 60
    /// How much of the page's right edge stays out of the band, for the scrollbar (Arc's grabber is
    /// the content's width less 14 pt).
    public static let trailingInset: Double = 14

    /// How far into the page the band reaches under a bar of that height (none: the whole 60 pt).
    public static func band(barHeight: Double) -> Double { max(0, reach - barHeight) }

    /// Whether a press can start a window drag: a plain single left click in the band, with the setting on.
    public static func holds(enabled: Bool, barHeight: Double, depthIntoPage: Double, clickCount: Int, modifiers: Bool,
                             distanceFromRight: Double = .infinity) -> Bool {
        enabled && clickCount == 1 && !modifiers
            && depthIntoPage >= 0 && depthIntoPage < band(barHeight: barHeight) && distanceFromRight > trailingInset
    }

    /// How long before a press Cra must have been active for the cursor to count.
    public static let activationSlack: Double = 0.1

    /// Whether the cursor at a press says what is under the pointer. Chromium sets it as the pointer moves
    /// over an active Cra. A press on an inactive Cra, or the press that brought it to the front, finds
    /// whatever cursor Cra set when it was last in front: an I-beam left behind kept such a drag from
    /// moving the window about every other time (found testing #335 with real drags). Times are the
    /// system's uptime, as an event's timestamp is.
    public static func cursorIsCurrent(appActive: Bool, becameActiveAt: Double, pressedAt: Double) -> Bool {
        appActive && becameActiveAt < pressedAt - activationSlack
    }
}
