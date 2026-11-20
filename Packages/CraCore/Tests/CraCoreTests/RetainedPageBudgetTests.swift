import CraCore
import Foundation
import Testing

struct RetainedPageBudgetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func slept(_ n: Int) -> [RetainedPageBudget.Page] {
        (0..<n).map { i in .init(id: UUID(), discarded: true, hiddenAt: now.addingTimeInterval(-Double(i) * 60), visible: false, busy: false) }
    }

    /// GitHub #616: every page shown in a session kept its browser, window and thumbnail after tab
    /// sleeping ended it. A window keeps its 32 most recently hidden slept pages; the oldest close, 8 a pass.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/616"))
    func aWindowKeepsItsLatestSleptPages() {
        let all = slept(100)
        var pages = all
        // The 8 hidden longest go first.
        let first = RetainedPageBudget.unloads(pages)
        #expect(first == pages.suffix(8).reversed().map(\.id))
        // Pass after pass it settles at 32, never below.
        var passes = 0
        while case let out = RetainedPageBudget.unloads(pages), !out.isEmpty {
            pages.removeAll { out.contains($0.id) }
            passes += 1
        }
        #expect(pages.count == 32 && passes == 9)
        #expect(Set(pages.map(\.id)) == Set(all.prefix(32).map(\.id)), "the 32 kept are the 32 hidden most recently")
    }

    /// Pages sleep keeps awake, pages on screen and pages not slept are never closed.
    @Test func onlySleptHiddenIdlePagesClose() {
        var pages = slept(40)
        pages[39] = .init(id: pages[39].id, discarded: true, hiddenAt: pages[39].hiddenAt, visible: false, busy: true)
        pages[38] = .init(id: pages[38].id, discarded: false, hiddenAt: pages[38].hiddenAt, visible: false, busy: false)
        pages[37] = .init(id: pages[37].id, discarded: true, hiddenAt: nil, visible: true, busy: false)
        let out = RetainedPageBudget.unloads(pages)
        #expect(!out.contains(pages[39].id) && !out.contains(pages[38].id) && !out.contains(pages[37].id))
        #expect(out == [pages[36].id, pages[35].id, pages[34].id, pages[33].id, pages[32].id])
        #expect(RetainedPageBudget.unloads(slept(32)).isEmpty)
    }

    /// Equal times close in id order, the same every pass.
    @Test func equalTimesCloseInAStableOrder() {
        let pages = (0..<40).map { _ in RetainedPageBudget.Page(id: UUID(), discarded: true, hiddenAt: now, visible: false, busy: false) }
        let a = RetainedPageBudget.unloads(pages), b = RetainedPageBudget.unloads(pages.shuffled())
        #expect(a == b && a.count == 8)
    }

    /// GitHub #616 (c): when hundreds of pages cross the four-hour line in one minute, the clock's pass asks
    /// 16 of them; the rest wait for the next minutes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/616"))
    func theTimerAsksSixteenPagesAPass() {
        #expect(TabSleepPolicy.timer(.fourHours).limit == 16 && TabSleepPolicy.timer(.fifteenMinutes).limit == 16)
        #expect(TabSleepPolicy.memoryPressure(.critical).limit == 9)
    }
}
