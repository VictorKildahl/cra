import AppKit
import CraCEF

/// The performance recorder's app side, the one Perf file that sees Chromium (lint: perf-boundary):
/// renderer trouble and failed loads from CraCEF, the visible tab's long tasks and frames from
/// Cra's isolated world, tab counts from the windows, whether Cra is active and on screen, and
/// the Settings switch.
@MainActor
enum PerfCEF {
    /// From AppDelegate.bootstrapIfNeeded.
    static func install(app: AppDelegate) {
        CraCEFRuntime.setProcessEventHandler { kind, detail, site in
            switch kind {
            case "terminated":
                Perf.count(.rendererTerminated, detail, site: site)
                // A page process that can't start ("launch failed", or a crash in its first moments, ICU's data
                // gone) is how a Cra.app replaced under this copy shows first; the check is one Info.plist read.
                SoftwareUpdater.shared.checkInstalledBundle()
            case "unresponsive": Perf.count(.rendererUnresponsive, site: site)
            case "responsive": Perf.count(.rendererResponsive, site: site)
            case "loadError": Perf.count(.loadError, detail, site: site)
            default: break
            }
        }
        PerfRecorder.runawayHandler = { [weak app] found in
            guard let app else { return }
            logRunaways(found, app)
        }
        var samples = 0
        PerfRecorder.mainSampler = { [weak app] recorder in
            guard let app else { return }
            let start = MainLoopObserver.threadCPU()
            samples += 1
            if samples % 12 == 1 { readProcessSites(app, recorder) }
            recorder.tabs(tabCounts(app))
            recorder.userIdle(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= 60)
            if let browser = app.main?.currentBrowser, browser.isCreated, !browser.isClosed { readPage(browser, recorder) }
            recorder.addMainThreadCost(ns: MainLoopObserver.threadCPU() &- start)
        }
        observeApp(app)
        let environment = ProcessInfo.processInfo.environment
        observeChanges(of: { [store = app.store] in store.settings.perfRecording }) { on in
            PerfRecorder.setRecording(PerfSessionRules.recording(setting: on, environment: environment))
        }
    }

    /// Every live page, with where it is: what a runaway line lists and what the sites refresh asks.
    private static func livePages(_ app: AppDelegate) -> [(rt: TabRuntime, manager: BrowserManager, shown: Bool, state: String)] {
        app.mainWindows.compactMap(\.browsers).flatMap { m in
            m.runtimes.values.filter { !$0.discarded && $0.browser.isCreated && !$0.browser.isClosed }.map { rt in
                let shown = m.visibleTabIDs.contains(rt.tabID)
                let state = rt.browser.isInPictureInPicture ? "Picture in Picture"
                    : !shown ? "hidden" : m.windowCovered ? "shown, window covered" : "shown"
                return (rt, m, shown || rt.browser.isInPictureInPicture, state)
            }
        }
    }

    /// The engine's Cra.getProcessInfo: each frame's process and site (`frames: [{pid, site, main}]`).
    /// An engine without it says so once and isn't asked again.
    private static var processInfoMissing = false

    private static func processInfo(_ browser: CraBrowser, _ done: @escaping @MainActor ([(pid: Int32, site: String, main: Bool)]?) -> Void) {
        guard !processInfoMissing else { done(nil); return }
        browser.sendDevToolsMethod("Cra.getProcessInfo", params: "{}") { result, error in
            let frames = ((result?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["frames"]
                as? [[String: Any]])?.compactMap { f -> (pid: Int32, site: String, main: Bool)? in
                    guard let pid = f["pid"] as? Int else { return nil }
                    return (Int32(pid), f["site"] as? String ?? "", f["main"] as? Bool ?? false)
                }
            DispatchQueue.main.async {
                if frames == nil, error != nil { processInfoMissing = true }
                done(frames)
            }
        }
    }

    /// Once a minute: which sites have a frame in each renderer, for the history's largest and
    /// busiest process. Only the host, as the log has it.
    private static func readProcessSites(_ app: AppDelegate, _ recorder: PerfRecorder) {
        let pages = livePages(app)
        guard !processInfoMissing, !pages.isEmpty else { return }
        var sites: [Int32: [String]] = [:]
        var left = pages.count
        for page in pages {
            processInfo(page.rt.browser) { frames in
                for f in frames ?? [] where !f.site.isEmpty && !page.rt.browser.isIncognito {
                    let host = CraLog.host("https://" + f.site)
                    if !(sites[f.pid]?.contains(host) ?? false) { sites[f.pid, default: []].append(host) }
                }
                left -= 1
                if left == 0 { recorder.processSites(sites) }
            }
        }
    }

    /// A process that grew past 2, 4, 8… GB or kept two cores busy for 30 s, and every live page:
    /// where it is, the process of each of its frames (with the engine's Cra.getProcessInfo), its
    /// JavaScript heap, and whether it answered at all within 3 s (a renderer pinned at 100 % of
    /// its main thread doesn't). A 0.1.44 report had 14-17 GB with four tabs and no way to tell whose.
    private static func logRunaways(_ found: [PerfRunaway], _ app: AppDelegate) {
        func gb(_ bytes: Int64) -> String {
            bytes < 1 << 30 ? "\(bytes >> 20) MB" : String(format: "%.1f GB", Double(bytes) / Double(1 << 30))
        }
        for r in found {
            let u = r.usage
            let what: String
            switch r.reason {
            case .memory(let level): what = "passed \(level) GB"
            case .cpu: what = "over \(Int(PerfRunawayWatch.busyPct)) % of a core for 30 s"
            }
            CraLog.note("perf: \(u.kind.rawValue) pid \(u.pid) \(what) (\(gb(u.footprintBytes)), \(Int(u.cpuPct)) % CPU)")
        }
        let pages = livePages(app)
        var procs = [String?](repeating: nil, count: pages.count), heaps = procs
        var pids = [Set<Int32>](repeating: [], count: pages.count)
        var left = pages.count * 2
        var logged = false
        let finish = {
            guard !logged else { return }
            logged = true
            for (i, page) in pages.enumerated() {
                let parts = [procs[i], heaps[i]].compactMap { $0 }
                let site = page.rt.browser.isIncognito ? "(incognito)" : CraLog.host(page.rt.browser.currentURL)
                CraLog.note("perf: page \(site) \(page.state): \(parts.isEmpty ? "no answer in 3 s" : parts.joined(separator: "; "))")
            }
            sleepRunaways(found, pages: pages, pids: pids)
        }
        let done = { left -= 1; if left == 0 { finish() } }
        for (i, page) in pages.enumerated() {
            processInfo(page.rt.browser) { frames in
                if let frames {
                    pids[i] = Set(frames.map(\.pid))
                    let main = frames.first { $0.main }.map { "pid \($0.pid)" } ?? "no live frame"
                    let others = page.rt.browser.isIncognito ? [] : frames.filter { !$0.main }
                        .map { "\($0.site.isEmpty ? "(no site)" : CraLog.host("https://" + $0.site)) pid \($0.pid)" }
                    procs[i] = main + (others.isEmpty ? "" : ", frames " + others.joined(separator: ", "))
                }
                done()
            }
            page.rt.browser.sendDevToolsMethod("Runtime.getHeapUsage", params: "{}") { result, _ in
                let heap = (result?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async {
                    if let used = heap?["usedSize"] as? Double {
                        heaps[i] = "JS heap \(gb(Int64(used)))" + ((heap?["backingStorageSize"] as? Double).map { ", buffers \(gb(Int64($0)))" } ?? "")
                    }
                    done()
                }
            }
        }
        if pages.isEmpty { CraLog.note("perf: no live pages") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish() }
    }

    /// PerfRunawaySleep.bytes, or CRA_RUNAWAY_SLEEP_GB for a scenario that can't hold 8 GB.
    private static let runawaySleepBytes: Int64 = ProcessInfo.processInfo.environment["CRA_RUNAWAY_SLEEP_GB"]
        .flatMap(Int64.init).map { $0 << 30 } ?? PerfRunawaySleep.bytes

    /// A page process past PerfRunawaySleep.bytes: the hidden pages with a frame in it sleep, counted
    /// for the Performance pane's insight. Without the engine's pids nothing says which pages.
    private static func sleepRunaways(_ found: [PerfRunaway], pages: [(rt: TabRuntime, manager: BrowserManager, shown: Bool, state: String)],
                                      pids: [Set<Int32>]) {
        for r in found where PerfRunawaySleep.applies(r, bytes: runawaySleepBytes) {
            let size = String(format: "%.1f GB", Double(r.usage.footprintBytes) / Double(1 << 30))
            guard !processInfoMissing else {
                CraLog.note("perf: can't tell which pages pid \(r.usage.pid) holds (an engine without Cra.getProcessInfo), none sleep")
                continue
            }
            let candidates = pages.indices.map { (id: $0, pids: pids[$0], shown: pages[$0].shown) }
            let chosen = PerfRunawaySleep.pages(for: r.usage.pid, among: candidates)
            if chosen.isEmpty {
                let shown = candidates.contains { $0.pids.contains(r.usage.pid) }
                CraLog.note("perf: pid \(r.usage.pid) \(shown ? "holds a page on screen" : "holds no page"), none sleep")
            }
            for i in chosen {
                let page = pages[i]
                guard page.manager.sleepRunaway(page.rt.tabID) else { continue }
                let site = page.rt.browser.isIncognito ? nil : CraLog.host(page.rt.browser.currentURL)
                Perf.count(.runawaySlept, size, site: site)
            }
        }
    }

    /// kCGAnyInputEventType.
    private static let anyInput = CGEventType(rawValue: ~0)!

    /// Breadcrumbs for what most often comes right before a stall that no Cra action explains
    /// (GitHub #135), and the state every stall is tagged with.
    private static func observeApp(_ app: AppDelegate) {
        var last: (active: Bool, onScreen: Bool)?
        let update = { [weak app] in
            guard let app else { return }
            let now = (NSApp.isActive, app.mainWindows.contains { $0.window?.occlusionState.contains(.visible) == true })
            guard last.map({ $0 != now }) ?? true else { return }
            last = now
            Perf.app(active: now.0, onScreen: now.1)
        }
        let center = NotificationCenter.default
        let marks: [(Notification.Name, String?)] = [
            (NSApplication.didBecomeActiveNotification, "app-active"), (NSApplication.didResignActiveNotification, "app-inactive"),
            (NSWindow.willEnterFullScreenNotification, "fullscreen-enter"), (NSWindow.willExitFullScreenNotification, "fullscreen-exit"),
            (NSWindow.didChangeOcclusionStateNotification, nil),
        ]
        for (name, mark) in marks {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if let mark { HitchMonitor.mark(mark) }
                    update()
                }
            }
        }
        update()
    }

    private static func tabCounts(_ app: AppDelegate) -> PerfTabCounts {
        let managers = app.mainWindows.compactMap(\.browsers)
        return PerfTabCounts(tabs: app.store.items.tabCount,
                             live: managers.reduce(0) { $0 + $1.runtimes.values.filter { !$0.discarded }.count },
                             visible: managers.reduce(0) { $0 + $1.visibleTabIDs.count },
                             slept: managers.reduce(0) { $0 + $1.sleptTabs.count },
                             incognito: managers.reduce(0) { $0 + $1.runtimes.values.filter { $0.browser.isIncognito }.count },
                             windows: app.mainWindows.filter { $0.window?.isVisible == true }.count)
    }

    /// Reads and resets the counters PageScript keeps in `__cra.lt` (long tasks) and `__cra.lf`
    /// (long animation frames), and the frames the page's videos played and dropped since the last
    /// read (`getVideoPlaybackQuality`, remembered per element). A page without them (Cra's own
    /// pages, one still loading) or with nothing to say answers null.
    private static let readPageParams: String = {
        let js = """
            (() => { const c = window.__cra, l = c?.lt; if (!l) return null;
              const f = c.lf || { n: 0, max: 0 }, q = c.vq || (c.vq = new WeakMap()); let vt = 0, vd = 0;
              for (const v of document.getElementsByTagName('video')) {
                if (!(v instanceof HTMLVideoElement)) continue;
                const p = v.getVideoPlaybackQuality(), o = q.get(v) || [0, 0], b = p.totalVideoFrames < o[0] ? [0, 0] : o;
                vt += p.totalVideoFrames - b[0]; vd += p.droppedVideoFrames - b[1]; q.set(v, [p.totalVideoFrames, p.droppedVideoFrames]);
              }
              if (!l.n && !f.n && !vt) return null;
              const r = JSON.stringify([l.n, l.t, l.d, f.n, f.max, vt, vd]);
              l.n = 0; l.t = 0; l.d = []; f.n = 0; f.max = 0; return r; })()
            """
        let params: [String: Any] = ["expression": js, "returnByValue": true]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: params)) ?? Data(), as: UTF8.self)
    }()

    private static func readPage(_ browser: CraBrowser, _ recorder: PerfRecorder) {
        browser.evaluate(inIsolatedWorld: PageScript.world, params: readPageParams) { [weak recorder] result, _ in
            guard let data = result?.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let value = (json["result"] as? [String: Any])?["value"] as? String,
                  let fields = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [Any], fields.count == 7,
                  let count = fields[0] as? Int, let total = fields[1] as? Double else { return }
            let durations = (fields[2] as? [Double]) ?? []
            let frames = PerfPageFrames(longFrames: fields[3] as? Int ?? 0, longestFrameMs: fields[4] as? Double ?? 0,
                                        videoFrames: fields[5] as? Int ?? 0, droppedVideoFrames: fields[6] as? Int ?? 0)
            DispatchQueue.main.async {
                recorder?.pageLongTasks(count: count, totalMs: total, durations: durations)
                recorder?.pageFrames(frames)
            }
        }
    }
}
