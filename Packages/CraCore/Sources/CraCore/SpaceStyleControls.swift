import CoreGraphics
import Foundation

/// The theme editor's intensity slider and grain dial as Arc 1.173.1 has them (its SpaceStyleEditor
/// code, and a 120 Hz, 2x screen recording of the slider dragged end to end, 18 Nov 2026).
public enum SpaceStyleControls {
    // MARK: Ticks

    /// Arc plays a generic haptic tick (`performFeedbackPattern: 0`, now) whenever one of the two
    /// values crosses a step: its editor calls one helper with 0.1 for one value and 0.2 for the
    /// other (0x1017bcb0c, 0x1017bcd28). Which is which isn't certain from the code; the 0.2 one
    /// is held to 0…1 first, as a turned dial needs, so Cra gives the dial 0.2 and the slider 0.1.
    public static let intensityStep: Double = 0.1
    public static let grainStep: Double = 0.2

    /// Whether moving a value from `old` to `new` ticks: a multiple of `step` (0, step, 2 × step…
    /// up to 1) lies between them, ends included (0x1017bcf84).
    public static func ticks(from old: Double, to new: Double, step: Double) -> Bool {
        guard old != new, step > 0 else { return false }
        let lo = min(old, new), hi = max(old, new)
        var k = 0
        while Double(k) * step <= 1 + 1e-9 {
            let mark = Double(k) * step
            if mark >= lo - 1e-12, mark <= hi + 1e-12 { return true }
            k += 1
        }
        return false
    }

    // MARK: The slider

    /// The wave's height is its most times the value (Arc: strength = maxAmplitude × value), so it
    /// is a flat line at nothing. Measured: 33.5 pt from trough to crest at full, with a 5 pt line.
    public static let waveMaxAmplitude: CGFloat = 14.25
    public static let waveLine: CGFloat = 5
    /// The thumb's centre runs between points this far inside the slider's ends (202.8 pt of travel).
    public static let trackInset: CGFloat = 10.5
    /// Under the pointer or held, the thumb is a tenth larger, on a spring (0.25 s, damped 0.9).
    public static let heldScale: CGFloat = 1.1
    public static let heldSpring: (response: Double, damping: Double) = (0.25, 0.9)

    public static func waveAmplitude(value: Double) -> CGFloat {
        waveMaxAmplitude * CGFloat(min(max(value, 0), 1))
    }

    /// The thumb grows with the value: 11.5 × 40.5 pt at nothing, 25.5 × 53 pt at full (measured
    /// held, 12.5 × 44.5 and 28 × 58.5 pt).
    public static func thumbSize(value: Double, held: Bool) -> CGSize {
        let v = CGFloat(min(max(value, 0), 1)), k = held ? heldScale : 1
        return CGSize(width: (11.5 + 14 * v) * k, height: (40.5 + 12.7 * v) * k)
    }
}
