/// Arc's recording dot on a tab whose page uses the camera or microphone (ARCUI.RecordingDotIndicator,
/// TabCellView.hasLeadingRecordingIndicator), measured from a recording of Arc 1.173 in a Google Meet call
/// (X DM 19 Nov 2026, 1.22 pt to a pixel by the rows' 36 pt fill and 41 pt pitch):
/// - it leads the row: a 7 pt dot where the favicon would start, and the favicon, with the name after it,
///   moves 14 pt right (the dot and 7 pt of air);
/// - it pulses: its red brightens about a third of the way to white and back, about 0.75 s each way,
///   its size unchanged.
public enum RecordingDot {
    public static let diameter: Double = 7
    /// From the dot's trailing edge to the favicon.
    public static let gap: Double = 7
    /// How far the favicon, and everything after it, moves for the dot.
    public static var shift: Double { diameter + gap }
    /// How far toward white the red goes at the pulse's peak.
    public static let pulseWhite: Double = 0.35
    /// Red to its peak; the pulse comes back the same way and repeats.
    public static let pulseHalfPeriod: Double = 0.75

    /// Where a tab row's dot (nil without one) and favicon go, from `iconX`, the favicon's place without a dot.
    public static func leading(iconX: Double, recording: Bool) -> (dotX: Double?, iconX: Double) {
        recording ? (iconX, iconX + shift) : (nil, iconX)
    }
}
