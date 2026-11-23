import CoreGraphics
import Foundation

/// A Document Picture in Picture window (`documentPictureInPicture.requestWindow`, Google Meet's
/// call window) dragged by the user. It is Chromium's own window: the system moves it by its top
/// bar, so Cra only hears that it moved and, later, that the mouse button came up.
///
/// Let go partly past the screen's edge, it slides back the shortest way onto the display most of
/// it is on, 10 pt in from the edges it crossed, at its own size: Arc 1.173's Document PiP, let go
/// half past the left edge, came back to 10 pt from that edge at the same height (live, 23 Nov
/// 2026, #702). A video's Picture in Picture goes into a corner instead (#332).
///
/// Only a move made while the button was held counts: a site resizing its window, a window
/// manager moving it (Rectangle, over Accessibility) or Cra's own slide don't start one.
public struct DocumentPictureInPictureDrag: Equatable, Sendable {
    public private(set) var isDragging = false

    public init() {}

    /// The window moved; `buttonDown`: the left mouse button was held when it did.
    public mutating func moved(buttonDown: Bool) {
        if buttonDown { isDragging = true }
    }

    /// The button came up with the window at `frame`. Where it slides to, or nil when it wasn't
    /// dragged or is wholly on screen (under the menu bar or the Dock too).
    public mutating func released(frame: CGRect, displays: [PictureInPictureLayout.Display]) -> CGRect? {
        defer { isDragging = false }
        guard isDragging, PictureInPictureLayout.landing(afterDropping: frame, displays: displays) != nil,
              let display = PictureInPictureLayout.display(holding: frame, in: displays) else { return nil }
        let room = display.visible.insetBy(dx: PictureInPictureLayout.edgeMargin, dy: PictureInPictureLayout.edgeMargin)
        let end = PictureInPictureLayout.fit(frame, into: room)
        return end == frame ? nil : end
    }

    /// Whether a window is a Document Picture in Picture one: Chromium's (`NativeWidgetMac…`),
    /// floating, top-level (Chromium's bubbles and menus are child windows) and not the video
    /// Picture in Picture window Cra dresses as Arc's.
    public static func isDocumentWindow(className: String, floating: Bool, hasParent: Bool, isVideo: Bool) -> Bool {
        className.hasPrefix("NativeWidgetMac") && floating && !hasParent && !isVideo
    }
}
