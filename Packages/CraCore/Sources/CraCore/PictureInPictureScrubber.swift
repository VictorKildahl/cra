import CoreGraphics

/// The scrubber on the Picture in Picture window, as in Arc 1.172: a 5 pt capsule along the
/// bottom, white over white 30 %, that shows how far the video is and seeks on a drag. A drag
/// that goes up seeks slower. A video with no end (a stream) has no scrubber. Points have their
/// origin at the window's bottom left, y going up.
public struct PictureInPictureScrubber: Sendable, Equatable {
    /// The capsule's height.
    public static let thickness: CGFloat = 5
    /// How tall the band is that takes the pointer (Arc: 15 pt, the capsule in its middle).
    public static let dragHeight: CGFloat = 15
    /// How far up the pointer goes for each halving of the seek rate.
    public static let slowStep: CGFloat = 60
    /// The slowest rate: 1/16.
    public static let slowestHalvings = 4

    /// Whether a video this long has a scrubber: only one with a known end.
    public static func shows(duration: Double) -> Bool { duration.isFinite && duration > 0 }

    /// The capsule in a window of `size`: 8 pt above the bottom (4 in a tiny window, under 280 pt
    /// wide), as far in from the sides as the other controls (12 pt when tiny, 16 otherwise).
    public static func track(in size: CGSize) -> CGRect {
        let tiny = size.width < 280
        let inset: CGFloat = tiny ? 12 : 16
        return CGRect(x: inset, y: tiny ? 4 : 8, width: max(size.width - 2 * inset, 0), height: thickness)
    }

    /// The band a press seeks in: 15 pt tall around the capsule, without the strip along the
    /// bottom edge that resizes the window (`PictureInPictureGesture.grip`).
    public static func dragArea(in size: CGSize) -> CGRect {
        let t = track(in: size)
        let band = CGRect(x: t.minX, y: t.midY - dragHeight / 2, width: t.width, height: dragHeight)
        let floor = PictureInPictureGesture.grip
        guard band.maxY > floor else { return .zero }
        return CGRect(x: band.minX, y: max(band.minY, floor), width: band.width, height: band.maxY - max(band.minY, floor))
    }

    /// How much of the capsule is filled: 0 at the start, 1 at the end.
    public static func fraction(position: Double, duration: Double) -> CGFloat {
        guard shows(duration: duration), position.isFinite else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    /// The seek rate with the pointer `dy` above where it was pressed: 1 on the capsule, halved
    /// for each 60 pt up (2^round(dy / 60)), down to 1/16. Below the press it stays 1.
    public static func rate(above dy: CGFloat) -> Double {
        let halvings = min(max(Int((dy / slowStep).rounded()), 0), slowestHalvings)
        return 1 / Double(1 << halvings)
    }

    public let duration: Double
    public let trackWidth: CGFloat
    /// Where the video is with the drag so far, in seconds.
    public private(set) var position: Double
    private let pressY: CGFloat
    private var lastX: CGFloat

    /// A press at `point` on a window of `size` showing a video `duration` seconds long. The
    /// video goes to the pressed spot on the capsule.
    public init?(press point: CGPoint, in size: CGSize, duration: Double) {
        let track = Self.track(in: size)
        guard Self.shows(duration: duration), track.width > 0 else { return nil }
        self.duration = duration
        trackWidth = track.width
        pressY = point.y
        lastX = point.x
        position = Double(min(max((point.x - track.minX) / track.width, 0), 1)) * duration
    }

    /// The pointer is at `point`: the video moves by the way it went along the capsule since the
    /// last point, at the rate its height above the press gives. Returns the new position.
    @discardableResult
    public mutating func move(to point: CGPoint) -> Double {
        let dx = point.x - lastX
        lastX = point.x
        position = min(max(position + Double(dx / trackWidth) * duration * Self.rate(above: point.y - pressY), 0), duration)
        return position
    }
}
