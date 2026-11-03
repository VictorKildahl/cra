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
            case "terminated": Perf.count(.rendererTerminated, detail, site: site)
            case "unresponsive": Perf.count(.rendererUnresponsive, site: site)
            case "responsive": Perf.count(.rendererResponsive, site: site)
            case "loadError": Perf.count(.loadError, detail, site: site)
            default: break
            }
        }
        PerfRecorder.mainSampler = { [weak app] recorder in
            guard let app else { return }
            let start = MainLoopObserver.threadCPU()
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
        return PerfTabCounts(tabs: app.store.allTabs().count,
                             live: managers.reduce(0) { $0 + $1.runtimes.count },
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
