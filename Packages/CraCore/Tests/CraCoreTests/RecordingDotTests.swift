import CraCore
import Testing

/// Arc's recording dot (X DM 19 Nov 2026, Arc 1.173 recording with Google Meet).
struct RecordingDotTests {
    /// The dot leads the row where the favicon would start, and the favicon moves 14 pt right; Cra had the dot
    /// at the row's end.
    @Test func dotLeadsAndPushesTheFavicon() {
        let l = RecordingDot.leading(iconX: 10, recording: true)
        #expect(l.dotX == 10)
        #expect(l.iconX == 24)
        #expect(l.iconX - (l.dotX! + RecordingDot.diameter) == RecordingDot.gap)
    }

    /// Without a recording nothing moves.
    @Test func noDotNoShift() {
        let l = RecordingDot.leading(iconX: 26, recording: false)
        #expect(l.dotX == nil)
        #expect(l.iconX == 26)
    }

    /// A nested tab's dot follows its indent.
    @Test func nestedRowKeepsItsIndent() {
        let l = RecordingDot.leading(iconX: 26, recording: true)
        #expect(l.dotX == 26)
        #expect(l.iconX == 40)
    }
}
