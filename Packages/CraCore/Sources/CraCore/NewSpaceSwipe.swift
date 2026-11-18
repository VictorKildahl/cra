import CoreGraphics
import Foundation

/// Arc's "+" past the last space, from Arc 1.173.1's code (`ARCUI.EdgeFeedbackView` at
/// 0x1009dc240, driven from 0x100215f1c and 0x10021d960) and a 120 Hz, 2x screen recording read
/// frame by frame (18 Nov 2026). A swipe left on the last space overscrolls the tab list on its
/// rubber band, and that overscroll drives everything:
///
/// - 15 pt of it brings the edge's feedback fully out: a 30 pt disc from past the sidebar's right
///   edge, and behind it a soft bulge of the sidebar's ink that is widest at the disc.
/// - 22.5 pt fills the disc's ring. Full, the disc turns over with a tick, and a lift then starts
///   a new space, if the ring had been full for a tenth of a second. Less, or a pull back first,
///   and nothing happens.
///
/// The disc and the bulge don't follow the overscroll itself but a spring toward it, which is
/// what gives the edge its elastic feel.
public enum NewSpaceSwipe {
    // MARK: What the overscroll asks for (0x100215fc8…0x100216064)

    /// Overscroll past the last space, in points, at which the feedback is fully out.
    public static let showDistance: CGFloat = 15
    /// Overscroll at which the ring is full.
    public static let fillDistance: CGFloat = 22.5
    /// How long the ring must have been full for a lift to make a space (0x10021d998).
    public static let holdBeforeLift: TimeInterval = 0.1

    /// Arc's rubber band past the end of its pages, measured past the Library (docs/arc-reverse-
    /// engineering.md, "Swipe into the Library": 300 px of fingers moved it 20.5 pt, fitting
    /// D(1 − 1/(0.15 x / D + 1)) with x half the fingers' travel). It is about a quarter as giving as
    /// the band Cra's space swipe has past its ends, which is why Arc's ring fills slowly: some
    /// 330 pt of fingers in a 254 pt sidebar. `travel` is the fingers' travel past the last space.
    public static func overscroll(travel: CGFloat, page: CGFloat) -> CGFloat {
        guard travel > 0, page > 0 else { return 0 }
        return page * (1 - 1 / (0.15 * (travel / 2) / page + 1))
    }

    /// Where a new space can be made: not in a window that has no spaces of its own.
    public static func isOffered(standalone: Bool) -> Bool { !standalone }

    /// How far out the feedback should be, 0 to 1: what the spring heads for.
    public static func shown(overscroll: CGFloat) -> CGFloat { unit(overscroll / showDistance) }

    /// The ring, 0 to 1.
    public static func progress(overscroll: CGFloat) -> CGFloat { unit(overscroll / fillDistance) }

    public static func isActivated(overscroll: CGFloat) -> Bool { overscroll >= fillDistance }

    /// A lift makes a space when the ring has been full for longer than `holdBeforeLift`;
    /// `fullFor` is nil when it isn't full.
    public static func createsOnLift(fullFor: TimeInterval?) -> Bool {
        fullFor.map { $0 > holdBeforeLift } ?? false
    }

    // MARK: The edge's feedback, laid out (0x1009dc644…0x1009dc8b8, 0x1009dcbec)

    /// The feedback is a strip at the sidebar's right edge, as tall as the sidebar, that clips what
    /// it draws. Its width isn't in the code read; the bulge in the recording is 81 to 84 pt deep.
    public static let stripWidth: CGFloat = 82
    public static let disc: CGFloat = 30
    /// The disc rests with its right edge 12 pt inside the strip's, and starts 5 pt past it.
    public static let discRestGap: CGFloat = 12
    public static let discStartPast: CGFloat = 5
    /// The ring's line (0x10039f438) and the plus, 12 pt across in the recording.
    public static let ring: CGFloat = 2.5
    public static let glyph: CGFloat = 12
    public static let glyphStroke: CGFloat = 1.5
    /// The bulge is the sidebar's ink at this strength where it is strongest (0x10031641c).
    public static let bulgeAlpha: CGFloat = 0.22
    /// The disc grows to this as it turns over (57 to 65 px in the recording), within 0.2 s.
    public static let pop: CGFloat = 1.14
    public static let popDuration: Double = 0.2

    /// The disc in a strip of that size (origin top left), with the feedback `shown` out.
    public static func discFrame(shown v: CGFloat, strip: CGSize) -> CGRect {
        let start = strip.width + discStartPast, rest = strip.width - discRestGap - disc
        return CGRect(x: start + unit(v) * (rest - start), y: (strip.height - disc) / 2, width: disc, height: disc)
    }

    /// The disc fades in over the first fifth of the way.
    public static func discAlpha(shown v: CGFloat) -> CGFloat { unit(v / 0.2) }

    /// The bulge is a radial gradient in a layer twice the strip's width and as tall: strongest at
    /// its centre, nothing at its rim. It slides in from 10 pt inside the strip's right edge until
    /// its centre is on that edge, so the strip shows its left half: an ellipse's worth of light,
    /// widest half way down.
    public static func bulgeFrame(shown v: CGFloat, strip: CGSize) -> CGRect {
        CGRect(x: (strip.width - 10) * (1 - unit(v)), y: 0, width: 2 * strip.width, height: strip.height)
    }

    /// The bulge is at full strength half way out.
    public static func bulgeOpacity(shown v: CGFloat) -> CGFloat { unit(2 * v) }

    private static func unit(_ x: CGFloat) -> CGFloat { min(max(0, x), 1) }

    // MARK: The spring (0x1009dcb50…0x1009dcb78)

    /// The spring the feedback rides toward `shown`: a response of 0.4 s, damped at 0.8, so it
    /// swings a little past and settles.
    public struct Spring: Equatable, Sendable {
        public static let response: Double = 0.4
        public static let damping: Double = 0.8
        public var value: Double
        public var velocity: Double

        public init(value: Double = 0, velocity: Double = 0) {
            self.value = value
            self.velocity = velocity
        }

        /// `dt` seconds on, heading for `target`: the damped oscillator's own solution, so a long
        /// frame can't make it run away.
        public mutating func advance(toward target: Double, by dt: Double) {
            guard dt > 0 else { return }
            let w0 = 2 * Double.pi / Self.response, z = Self.damping
            let wd = w0 * (1 - z * z).squareRoot()
            let x0 = value - target
            let b = (velocity + z * w0 * x0) / wd
            let e = exp(-z * w0 * dt), c = cos(wd * dt), s = sin(wd * dt)
            value = target + e * (x0 * c + b * s)
            velocity = e * ((b * wd - z * w0 * x0) * c - (x0 * wd + z * w0 * b) * s)
        }

        /// At rest on `target`: nothing left to draw.
        public func isSettled(on target: Double) -> Bool {
            abs(value - target) < 0.001 && abs(velocity) < 0.01
        }
    }

    // MARK: Colours

    public struct Color: Equatable, Sendable {
        public let red, green, blue, alpha: CGFloat
        public init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
    }

    public struct Look: Equatable, Sendable {
        /// The disc's inside.
        public let fill: Color
        public let ring: Color
        public let plus: Color
    }

    /// Arc's `AddSpacePlus…` colours (its asset catalog), which have a dark and a light variant.
    /// `dark` is the app's appearance, not the space's: in macOS Dark Mode Arc's disc is white on
    /// every space (the recording's dark space: ring white 93 %, plus white 80 %, turned over a
    /// plus of black 68 %; on other spaces by the report of the Arc user it was built with). The
    /// light variant, #2702C2, wasn't seen.
    public static func look(activated: Bool, dark: Bool) -> Look {
        // AddSpacePlusProgressColor and …IconTintColor: white, or #2702C2 (Display P3).
        let accent = dark ? Color(1, 1, 1, 0.93) : Color(0.153, 0.008, 0.761, 1)
        // AddSpacePlusBackgroundColor at 22 %: black, or white.
        let back = dark ? Color(0, 0, 0, 0.22) : Color(1, 1, 1, 0.22)
        // AddSpacePlusIconActivatedTintColor: black, or white.
        let turned = dark ? Color(0, 0, 0, 0.68) : Color(1, 1, 1, 1)
        return activated ? Look(fill: accent, ring: accent, plus: turned)
                         : Look(fill: back, ring: accent, plus: dark ? Color(1, 1, 1, 0.8) : accent)
    }
}
