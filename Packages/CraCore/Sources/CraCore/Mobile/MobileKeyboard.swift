import CoreGraphics

/// How much of the iPhone app's screen the keyboard covers, from UIKit's keyboard notifications.
///
/// A frame change alone can't say the keyboard is gone: when the search sheet closes, iOS 27 fades
/// the keyboard out where it is, so its last end frame is still on screen (GitHub #505). It
/// covers something only between a show and a hide, and only the part of its frame on screen.
public struct MobileKeyboard: Equatable {
    public enum Event {
        case willShow, willChangeFrame, willHide, didHide
    }

    /// The keyboard's last end frame, in the view's coordinates.
    private var frame: CGRect = .zero
    private var shown = false

    public init() {}

    public mutating func apply(_ event: Event, endFrame: CGRect) {
        frame = endFrame
        switch event {
        case .willShow: shown = true
        case .willHide, .didHide: shown = false
        case .willChangeFrame: break
        }
    }

    /// The keyboard's reach up from the bottom of `bounds`.
    public func height(in bounds: CGRect) -> CGFloat {
        guard shown else { return 0 }
        let covered = frame.intersection(bounds)
        guard !covered.isNull, !covered.isEmpty else { return 0 }
        return bounds.maxY - covered.minY
    }
}
