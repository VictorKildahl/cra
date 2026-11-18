/// What reaches Chromium's video Picture in Picture window under Cra's overlay (GitHub #460).
///
/// Cra keeps Chromium's window for the video's pixels and draws Arc's controls over it in a window
/// of its own, which takes every click, hover, scroll and drag. Chrome's VideoOverlayWindowViews
/// shows its own controls (origin strip, Back to Tab, ±10 s, play/pause, progress bar, captions)
/// whenever its window gets a mouse move or enters, a key, a tap, or becomes key, so anything that
/// reaches it puts a second set under Arc's. Keeping the pointer and the key away from it
/// (`ignoresMouseEvents`, Chromium's `preventKeyWindow`, #262) wasn't enough on 0.1.48: a YouTube
/// PiP showed both. So the window takes no input of any kind and never becomes key; only the
/// system's own events (AppKit's, the app's, periodic ones) still go through.
public enum PictureInPictureInput {
    /// An event, by what it is to Chromium's window.
    public enum Kind: Sendable, CaseIterable {
        case mouseMove
        /// Pressed, released or dragged, any button (and pressure).
        case mouseButton
        /// A tracking area's entered or exited.
        case trackingArea
        case cursorUpdate
        case scroll
        /// Key down or up, and modifier changes.
        case key
        /// Trackpad and tablet gestures: magnify, rotate, swipe, smart magnify, touches.
        case gesture
        /// AppKit-defined, system-defined, application-defined and periodic events.
        case system
    }

    /// Whether Chromium's PiP window handles an event of this kind: only the system's.
    public static func chromiumTakes(_ kind: Kind) -> Bool {
        kind == .system
    }

    /// Chromium's PiP window never becomes key: becoming key alone shows Chrome's controls.
    public static let chromiumCanBecomeKey = false
}
