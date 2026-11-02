import Foundation

/// A click on the address while the command bar is open takes focus from the bar, which closes
/// it, and then its mouse-up asked for the bar again: it reopened at once with a fresh query.
/// Arc 1.170 closes the bar on that click and opens it only on the next one (GitHub #88). Times
/// are event times, seconds since boot; synthetic clicks share event numbers, so the latest
/// mouse-down's time is what identifies a click.
public struct DismissingClick: Equatable {
    private var closedAt: TimeInterval?

    public init() {}

    /// The bar closed while handling a mouse-down at `time`; nil when no click closed it.
    public mutating func panelClosed(byMouseDownAt time: TimeInterval?) {
        closedAt = time
    }

    /// A mouse-up asks to open the bar and the latest mouse-down was at `lastMouseDown`: true when
    /// that is the click that closed it. Each close is consumed by the first ask.
    public mutating func isClosingClick(lastMouseDown: TimeInterval) -> Bool {
        defer { closedAt = nil }
        guard let closedAt else { return false }
        return abs(lastMouseDown - closedAt) < 0.05
    }
}
