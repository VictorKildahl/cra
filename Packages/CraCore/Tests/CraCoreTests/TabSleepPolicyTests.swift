import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ Tab Cleanup's two tab-sleeping switches (GitHub #153), on Arc's defaults.
struct TabSleepPolicyTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let visible = UUID()

    /// Pages hidden `minutes` ago, one per entry, plus the visible tab.
    func pages(hiddenMinutesAgo minutes: [Double]) -> [TabSleepPolicy.Page] {
        [TabSleepPolicy.Page(id: visible, hiddenAt: nil)]
            + minutes.map { TabSleepPolicy.Page(id: UUID(), hiddenAt: now.addingTimeInterval(-$0 * 60)) }
    }

    /// A settings file without the keys is 0.1.28: 4 hours, the 10 tabs used last kept, no
    /// sweep for memory pressure.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153"), .bug("https://github.com/VictorKildahl/cra/issues/136")) func defaultsAreArcs() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.tabSleepTimerEnabled && s.tabSleepAfter == .fourHours && !s.tabSleepOnMemoryPressure)
        let policy = TabSleepPolicy.timer(s.tabSleepAfter)
        #expect(policy == TabSleepPolicy(hiddenFor: 4 * 3600, keepsRecentTabs: true))
        #expect(!TabSleepPolicy.sweepsForPressure(.critical, enabled: s.tabSleepOnMemoryPressure, lastSweep: nil, now: now))
    }

    /// 0.1.22–0.1.27 saved their own switch; it neither turns the clock off nor sets its time.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func earlierSwitchIsIgnored() throws {
        let json = #"{"tabSleepEnabled": false, "tabSleep": "fifteenMinutes"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.tabSleepTimerEnabled && s.tabSleepAfter == .fourHours)
    }

    /// An unknown time (a later Cra's) falls back to 4 hours without resetting the file.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func unknownTimeFallsBack() throws {
        let json = #"{"tabSleepAfter": "fortnight", "searchEngine": "kagi"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.tabSleepAfter == .fourHours && s.searchEngine == .kagi)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func thresholds() {
        #expect(TabSleepThreshold.allCases.map(\.label) == ["15 minutes", "30 minutes", "1 hour", "2 hours", "4 hours", "8 hours"])
        #expect(TabSleepThreshold.allCases.map(\.seconds) == [900, 1800, 3600, 7200, 14400, 28800])
    }

    /// At 4 hours a page hidden 3 h 59 min stays and one hidden 4 h 1 min is a candidate, unless
    /// it is among the 10 tabs used last.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153"), .bug("https://github.com/VictorKildahl/cra/issues/136")) func fourHoursKeepsTheTenUsedLast() {
        let policy = TabSleepPolicy.timer(.fourHours)
        let p = pages(hiddenMinutesAgo: [239, 241])
        #expect(policy.candidates(p, visible: [visible], now: now) == [])
        #expect(policy.candidates(p, visible: [visible], protectedRecent: 2, now: now) == [p[2].id])
        let many = pages(hiddenMinutesAgo: (0..<12).map { 300 + Double($0) })
        // The visible tab and the 9 hidden most recently stay: the 3 hidden longest go, oldest first.
        #expect(policy.candidates(many, visible: [visible], now: now) == [many[12].id, many[11].id, many[10].id])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func eightHoursKeepsThemToo() {
        let p = pages(hiddenMinutesAgo: [9 * 60])
        #expect(TabSleepPolicy.timer(.eightHours).candidates(p, visible: [visible], now: now) == [])
        #expect(TabSleepPolicy.timer(.eightHours).candidates(p, visible: [visible], protectedRecent: 1, now: now) == [p[1].id])
    }

    /// Shorter than Arc's 4 hours, the 10 tabs used last are not kept: they hold the memory.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func shortTimesCloseTheTenUsedLast() {
        let p = pages(hiddenMinutesAgo: [14, 16])
        #expect(TabSleepPolicy.timer(.fifteenMinutes).candidates(p, visible: [visible], now: now) == [p[2].id])
        #expect(!TabSleepPolicy.timer(.twoHours).keepsRecentTabs)
    }

    /// The tab on screen and both panes of a split are never candidates, whatever their dates.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func visiblePagesStay() {
        let split = TabSleepPolicy.Page(id: UUID(), hiddenAt: now.addingTimeInterval(-86400))
        let p = pages(hiddenMinutesAgo: []) + [split]
        #expect(TabSleepPolicy.memoryPressure(.warning).candidates(p, visible: [visible, split.id], now: now) == [])
    }

    /// A page that played sound waits as long after it went quiet as after it went out of sight.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func recentlyAudibleStays() {
        let id = UUID()
        let hidden = now.addingTimeInterval(-3600)
        let quiet2 = TabSleepPolicy.Page(id: id, hiddenAt: hidden, audibleAt: now.addingTimeInterval(-120))
        let quiet20 = TabSleepPolicy.Page(id: id, hiddenAt: hidden, audibleAt: now.addingTimeInterval(-1200))
        #expect(TabSleepPolicy.timer(.fifteenMinutes).candidates([quiet2], visible: [], now: now) == [])
        #expect(TabSleepPolicy.timer(.fifteenMinutes).candidates([quiet20], visible: [], now: now) == [id])
        #expect(TabSleepPolicy.memoryPressure(.warning).candidates([quiet2], visible: [], now: now) == [])
    }

    /// Under pressure: oldest first, the 10 used last included, none left in the last 5 minutes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func pressureTakesTheOldestPastTheGrace() {
        let policy = TabSleepPolicy.memoryPressure(.warning)
        #expect(policy.limit == 3 && policy.reason == .memoryPressure)
        let p = pages(hiddenMinutesAgo: [4.98, 5.02, 30, 10])
        #expect(policy.candidates(p, visible: [visible], now: now) == [p[3].id, p[4].id, p[2].id])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func pressureSweepTiming() {
        #expect(!TabSleepPolicy.sweepsForPressure(.warning, enabled: false, lastSweep: nil, now: now))
        #expect(!TabSleepPolicy.sweepsForPressure(.normal, enabled: true, lastSweep: nil, now: now))
        #expect(!TabSleepPolicy.sweepsForPressure(.unknown, enabled: true, lastSweep: nil, now: now))
        #expect(TabSleepPolicy.sweepsForPressure(.warning, enabled: true, lastSweep: nil, now: now))
        #expect(TabSleepPolicy.sweepsForPressure(.critical, enabled: true, lastSweep: nil, now: now))
    }

    /// The minute's pass is 60 s apart give or take; at warning a sweep skips one pass (every
    /// 2 minutes, which the old 90 s already meant), at critical it sweeps every pass (#237).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/237")) func pressureSweepCadence() {
        func sweeps(_ level: PerfSystemSample.Pressure, after s: TimeInterval) -> Bool {
            TabSleepPolicy.sweepsForPressure(level, enabled: true, lastSweep: now.addingTimeInterval(-s), now: now)
        }
        #expect(!sweeps(.warning, after: 60.2) && sweeps(.warning, after: 119.8) && sweeps(.warning, after: 120.3))
        #expect(!sweeps(.critical, after: 20) && sweeps(.critical, after: 59.8) && sweeps(.critical, after: 60.2))
    }

    /// Critical is warning further along: the sweep closes 9 pages, not 3, so it keeps up with a
    /// burst of tabs opened faster than the clock closes them (#237: 5–7 YouTube tabs a minute).
    /// The 5-minute floor stays: a tab just left isn't closed under the user.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/237")) func criticalClosesMore() {
        let warning = TabSleepPolicy.memoryPressure(.warning), critical = TabSleepPolicy.memoryPressure(.critical)
        #expect(warning.limit == 3 && critical.limit == 9)
        #expect(warning.hiddenFor == 300 && critical.hiddenFor == 300 && !critical.keepsRecentTabs && critical.reason == .memoryPressure)
    }

    /// One line per pass, not one per page (#237: twelve identical lines in 40 ms). A single page
    /// reads as it did; the host follows the verb, as the scenarios expect.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/237")) func passLogIsOneLine() {
        var log = TabSleepPolicy.PassLog(reason: .timer)
        #expect(log.lines.isEmpty)
        log.closed(host: "127.0.0.1", hiddenFor: 20, discarded: true, processEnded: true)
        #expect(log.lines == ["tab sleep discards 127.0.0.1 (hidden 0 min, its renderer ended)"])
        log = TabSleepPolicy.PassLog(reason: .timer)
        for (m, ended) in [(15, true), (22, true), (18, false)] { log.closed(host: "www.youtube.com", hiddenFor: Double(m) * 60 + 30, discarded: true, processEnded: ended) }
        log.closed(host: "github.com", hiddenFor: 16 * 60, discarded: true, processEnded: false)
        log.closed(host: "localhost", hiddenFor: 17 * 60, discarded: false, processEnded: false)
        #expect(log.lines == ["tab sleep discards www.youtube.com ×3, github.com (4 pages hidden 15–22 min, 2 renderers ended)",
                              "tab sleep unloads localhost (hidden 17 min)"])
        var pressure = TabSleepPolicy.PassLog(reason: .memoryPressure)
        pressure.closed(host: "github.com", hiddenFor: 6 * 60, discarded: true, processEnded: false)
        #expect(pressure.lines == ["tab sleep discards github.com (hidden 6 min, the Mac is short of memory)"])
    }

    /// A sweep that asks no page says why (#237: two pressure sweeps logged their cap and then
    /// nothing; the pages were 2 and 4 minutes out of sight, under the 5-minute floor).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/237")) func emptySweepSaysWhy() {
        let policy = TabSleepPolicy.memoryPressure(.warning)
        let young = pages(hiddenMinutesAgo: [2, 4])
        #expect(policy.nothingToClose(young, visible: [visible], held: [:], waiting: 0, now: now)
                == "none of 2 hidden pages has been out of sight 5 min (longest 4 min)")
        #expect(policy.nothingToClose([], visible: [], held: [:], waiting: 0, now: now) == "no page is out of sight")
        #expect(policy.nothingToClose(pages(hiddenMinutesAgo: [30, 40]), visible: [visible], held: [.loading: 1, .devTools: 1], waiting: 0, now: now)
                == "2 pages passed over (devTools 1, loading 1)")
        #expect(policy.nothingToClose(pages(hiddenMinutesAgo: [30]), visible: [visible], held: [:], waiting: 1, now: now)
                == "1 page refused lately, asked again later")
    }

    /// A pressure sweep that asked its pages and had every one refuse says so, with the reasons
    /// (#275: twelve sweeps after a wake, 3 pages asked and refused each time, wrote nothing but
    /// their header). The minute's timer pass stays quiet; a page it closed reads as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/275")) func sweepThatClosesNothingSaysWhy() {
        var pressure = TabSleepPolicy.PassLog(reason: .memoryPressure)
        for refusal in ["playing", "typed", "playing"] { pressure.refused(refusal) }
        #expect(pressure.lines == ["tab sleep for memory pressure closes nothing: 3 pages refused (playing 2, typed 1)"])
        var timer = TabSleepPolicy.PassLog(reason: .timer)
        timer.refused("typed")
        #expect(timer.lines.isEmpty)
        var mixed = TabSleepPolicy.PassLog(reason: .memoryPressure)
        mixed.refused("call")
        mixed.closed(host: "github.com", hiddenFor: 6 * 60, discarded: true, processEnded: false)
        #expect(mixed.lines == ["tab sleep discards github.com (hidden 6 min, the Mac is short of memory)"])
    }

    /// Waking the Mac runs a pass at once (#275: the first sweep came 24 minutes after the wake),
    /// and the timer's overdue fire right after it, or a second wake, doesn't run another.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/275")) func wakeRunsOnePass() {
        #expect(TabSleepPolicy.passDue(lastPass: nil, now: now))
        #expect(TabSleepPolicy.passDue(lastPass: now.addingTimeInterval(-7 * 3600), now: now), "a wake after a night runs a pass")
        #expect(!TabSleepPolicy.passDue(lastPass: now.addingTimeInterval(-1), now: now), "the overdue timer right after the wake's pass doesn't")
        #expect(!TabSleepPolicy.passDue(lastPass: now.addingTimeInterval(-20), now: now), "nor a second wake inside half a pass")
        #expect(TabSleepPolicy.passDue(lastPass: now.addingTimeInterval(-TabSleepPolicy.passInterval + 5), now: now),
                "the minute's timer, a little early, still runs")
    }

    /// Chromium's freezing reasons that keep a page from sleeping; the rest (a Web Lock, recently
    /// visible, notification permission) don't.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/153")) func freezingReasonsThatKeepAPage() {
        #expect(TabSleepPolicy.refusal(freezingReasons: ["has an active WebRTC connection", "holding Web Lock"]) == "call")
        #expect(TabSleepPolicy.refusal(freezingReasons: ["connected to USB device"]) == "device")
        #expect(TabSleepPolicy.refusal(freezingReasons: ["connected to serial port"]) == "device")
        #expect(TabSleepPolicy.refusal(freezingReasons: ["being mirrored"]) == "capturing")
        #expect(TabSleepPolicy.refusal(freezingReasons: ["capturing display"]) == "capturing")
        #expect(TabSleepPolicy.refusal(freezingReasons: ["holding Web Lock", "recently visible", "has notification permission"]) == "")
        #expect(TabSleepPolicy.refusal(freezingReasons: []) == "")
    }

    @Test func pressureLevels() {
        #expect([PerfSystemSample.Pressure.normal, .warning, .critical, .unknown].map(\.isShort) == [false, true, true, false])
    }

    /// Why a candidate stays awake without being asked, the first that holds (#214).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/214")) func holds() {
        let now = Date(timeIntervalSince1970: 10_000), cutoff = now.addingTimeInterval(-900)
        let idle = TabSleepPolicy.PageState(hiddenAt: now.addingTimeInterval(-3600))
        #expect(TabSleepPolicy.hold(idle, before: cutoff) == nil)
        func with(_ change: (inout TabSleepPolicy.PageState) -> Void) -> TabSleepPolicy.Hold? {
            var p = idle
            change(&p)
            return TabSleepPolicy.hold(p, before: cutoff)
        }
        #expect(with { $0.discarded = true } == .discarded)
        #expect(with { $0.visible = true } == .shown)
        #expect(with { $0.hiddenAt = nil } == .shown)
        #expect(with { $0.hiddenAt = now.addingTimeInterval(-60) } == .shown)
        #expect(with { $0.audibleAt = now.addingTimeInterval(-60) } == .sound)
        #expect(with { $0.audibleAt = now.addingTimeInterval(-3600) } == nil)
        #expect(with { $0.created = false } == .notCreated)
        #expect(with { $0.closed = true } == .closing)
        #expect(with { $0.loading = true } == .loading)
        #expect(with { $0.pictureInPicture = true } == .pictureInPicture)
        #expect(with { $0.capturing = true } == .capturing)
        #expect(with { $0.audible = true } == .audible)
        #expect(with { $0.devTools = true } == .devTools)
        #expect(with { $0.loading = true; $0.devTools = true } == .loading, "the first that holds is the one said")
        #expect(TabSleepPolicy.Hold.loading.rawValue == "loading", "the key in perf.json and the word in cra.log")
    }
}
