import CoreGraphics

/// A two-finger pinch on the Picture in Picture window resizes it, as Arc's does (#534): fingers
/// apart make it larger, together smaller, smoothly and in the video's shape, inside the same
/// limits as a resize from an edge. The window grows and shrinks around its centre and stays
/// on its display: a window resting in a corner (10 pt in) keeps that gap and grows out of the
/// corner, and one larger than the room left stops at the display's edges. Frames are AppKit
/// screen coordinates: origin at the bottom left, y going up.
public struct PictureInPicturePinch: Sendable {
    public let startFrame: CGRect
    /// How much larger the fingers have made the window so far: 1 at the start, 2 twice as wide.
    public private(set) var scale: CGFloat = 1

    /// The fingers touched down on a window at `frame`.
    public init(frame: CGRect) {
        startFrame = frame
    }

    /// The fingers moved apart by `magnification` (AppKit's `NSEvent.magnification`: 0.1 is 10 %
    /// larger, -0.1 is 10 % smaller, each event relative to the one before); returns the window's
    /// frame now, on a display whose visible frame is `visible`, sized inside `minSize` and
    /// `maxSize` (`PictureInPictureLayout.sizeLimits`). The scale stops where the window does, so
    /// fingers that went on past a limit take the window back as soon as they turn.
    public mutating func magnify(by magnification: CGFloat, minSize: CGSize, maxSize: CGSize, visible: CGRect) -> CGRect {
        let s = startFrame
        guard s.width > 0, s.height > 0 else { return s }
        let aspect = s.width / s.height
        let m = margins(in: visible)
        // The display's room less the gaps the window keeps to its edges.
        let roomW = visible.width - m.left - m.right, roomH = visible.height - m.bottom - m.top
        let lo = max(minSize.width, minSize.height * aspect)
        let hi = max(lo, min(maxSize.width, maxSize.height * aspect, roomW, roomH * aspect))
        if magnification.isFinite { scale *= max(1 + magnification, 0.01) }
        scale = min(max(scale, lo / s.width), hi / s.width)
        let w = (s.width * scale).rounded(), h = (w / aspect).rounded()
        // Around the centre, then back inside the room: a window in a corner keeps its corner.
        let x = (s.midX - w / 2).rounded(), y = (s.midY - h / 2).rounded()
        let minX = visible.minX + m.left, maxX = visible.maxX - m.right - w
        let minY = visible.minY + m.bottom, maxY = visible.maxY - m.top - h
        return CGRect(x: maxX < minX ? minX : min(max(x, minX), maxX),
                      y: maxY < minY ? minY : min(max(y, minY), maxY), width: w, height: h)
    }

    /// The gaps the window keeps to the visible frame's edges while it grows: the one it had,
    /// up to the 10 pt a corner leaves (`PictureInPictureLayout.edgeMargin`); none where it was
    /// already at or past the edge.
    func margins(in v: CGRect) -> (left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat) {
        let s = startFrame, cap = PictureInPictureLayout.edgeMargin
        func gap(_ d: CGFloat) -> CGFloat { min(max(d, 0), cap) }
        return (gap(s.minX - v.minX), gap(v.maxX - s.maxX), gap(s.minY - v.minY), gap(v.maxY - s.maxY))
    }
}
