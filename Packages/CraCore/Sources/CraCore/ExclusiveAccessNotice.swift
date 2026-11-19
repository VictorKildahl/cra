import Foundation

/// What Cra says when a page takes the screen or the pointer, as Arc does (docs/web-features.md). Chrome
/// decides the notice (its ExclusiveAccessBubbleType, which the engine hands over: CraExclusiveAccessNotice)
/// and hangs its own bubble on a window Cra's pages never show; Cra shows Arc's toast instead.
///
/// Arc 1.173.1, measured 19 Nov 2026 on a test page in Victor's Arc:
/// - a page's full screen in a browser window: "To exit full screen, press ⎋." at the top right; none in a
///   Little Arc;
/// - the page takes the pointer (requestPointerLock), browser window or Little Arc: "Your cursor is hidden.
///   Press 'esc' to show cursor.";
/// - full screen under the page's keyboard lock: the same full-screen toast (not Chrome's "press and hold").
///   A press of Esc is the page's, and Arc says "[⎋] again to exit fullscreen"; the next press while that shows
///   leaves full screen (KeyboardLockEscape).
public enum ExclusiveAccessNotice: Int, Equatable, Sendable {
    case none = 0
    case fullscreen = 1
    case fullscreenPointerLock = 2
    case pointerLock = 3
    case keyboardLock = 4
    /// The browser's own full screen, and an extension's: not a page's, and Arc shows nothing for them.
    case browserFullscreen = 5
    case extensionFullscreen = 6

    /// Arc's toast for a notice.
    public enum Toast: Equatable, Sendable {
        case exitFullscreen
        case pointerHidden

        public var text: String {
            switch self {
            case .exitFullscreen: "To exit full screen, press ⎋."
            case .pointerHidden: "Your cursor is hidden. Press 'esc' to show cursor."
            }
        }
    }

    /// The toast for this notice; `inLittleWindow`: the page is in a Little Window (Arc's Little Arc says
    /// nothing about full screen there, only about the pointer).
    public func toast(inLittleWindow: Bool) -> Toast? {
        switch self {
        case .fullscreen, .keyboardLock: inLittleWindow ? nil : .exitFullscreen
        case .pointerLock, .fullscreenPointerLock: .pointerHidden
        case .none, .browserFullscreen, .extensionFullscreen: nil
        }
    }
}

/// One page's notices: Chrome repeats the current one whenever something about full screen or the locks
/// changes; Arc's toast shows when it changes, or when Chrome asks again on purpose (the page asked again).
public struct ExclusiveAccessNotices: Equatable, Sendable {
    public private(set) var current: ExclusiveAccessNotice = .none

    public init() {}

    /// Chrome's notice for the page; the toast to show now, if any.
    public mutating func update(_ notice: ExclusiveAccessNotice, force: Bool, inLittleWindow: Bool) -> ExclusiveAccessNotice.Toast? {
        defer { current = notice }
        guard notice != current || force else { return nil }
        return notice.toast(inLittleWindow: inLittleWindow)
    }
}

/// Esc in a page's full screen while the page holds the keyboard (navigator.keyboard.lock: a cloud desktop, a
/// game). Arc: a press is the page's, and its toast offers "[⎋] again to exit fullscreen"; a press while that
/// toast shows leaves full screen. Times are event times in seconds.
public struct KeyboardLockEscape: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The page has the press; show the "again" toast.
        case offerAgain
        /// The press leaves full screen.
        case exitFullscreen
    }

    /// The key cap and the words after it, for ShinyToast.
    public static let againKeys = "⎋"
    public static let againText = "again to exit fullscreen"

    private var offeredAt: TimeInterval?

    public init() {}

    /// A press of Esc at `time`; `offerTime`: how long the "again" toast shows.
    public mutating func press(at time: TimeInterval, offerTime: TimeInterval) -> Outcome {
        if let offeredAt, time >= offeredAt, time - offeredAt <= offerTime {
            self.offeredAt = nil
            return .exitFullscreen
        }
        offeredAt = time
        return .offerAgain
    }

    /// Full screen ended (or the page let go of the keyboard): the next press starts over.
    public mutating func reset() {
        offeredAt = nil
    }
}
