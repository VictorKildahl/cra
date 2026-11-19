import Foundation

/// The sidebar list's overlay knob while two fingers rest on the trackpad. AppKit flashes an
/// overlay knob as soon as fingers touch over a list, and a swipe between spaces starts like that,
/// so a touch over the sidebar hides the knob until the gesture turns out to scroll the list (#77).
/// A touch while the knob already shows leaves it: scrolling a long list is flick after flick, each
/// touching down while the last one's momentum still moves the list, and hiding the knob at every
/// touch made it blink all the way down (#544). Times are event timestamps.
public struct ListKnobGate: Equatable, Sendable {
    /// How long AppKit keeps an overlay knob up after the list last moved.
    public static let shownAfterScroll: TimeInterval = 1

    public private(set) var hidden = false
    private var lastScroll: TimeInterval?

    public init() {}

    /// The list scrolled: the fingers moved it, its momentum did, or a wheel.
    public mutating func listScrolled(at time: TimeInterval) {
        lastScroll = time
        hidden = false
    }

    /// Fingers touched the trackpad over the sidebar.
    public mutating func touched(at time: TimeInterval) {
        if let lastScroll, time - lastScroll < Self.shownAfterScroll { return }
        hidden = true
    }

    /// The gesture scrolls the list, or a swipe ended and the touch's flash has faded.
    public mutating func reveal() { hidden = false }
}
