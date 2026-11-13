import CraCore
import Foundation
import Testing

/// Chromium's browser process gives back what closed tabs freed, once the user isn't using Cra.
struct MemoryReclaimTests {
    @Test func waitsOutInput() {
        #expect(!MemoryReclaim.runsNow(secondsSinceInput: 0.2))
        #expect(MemoryReclaim.runsNow(secondsSinceInput: 1))
        #expect(MemoryReclaim.runsNow(secondsSinceInput: 30))
    }

    @Test func settlesBeforeReclaiming() {
        // Closing ten tabs in a row reclaims once, after the last.
        #expect(MemoryReclaim.settle >= 5)
        #expect(MemoryReclaim.retry > 0)
    }
}
