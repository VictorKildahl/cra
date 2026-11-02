import AppKit
import CraCEF

/// The performance recorder's app side, the one Perf file that sees Chromium (lint: perf-boundary):
/// renderer trouble and failed loads from CraCEF, the visible tab's long tasks from Cra's isolated
/// world, tab counts from the windows, and the Settings switch.
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
            if let browser = app.main?.currentBrowser, browser.isCreated, !browser.isClosed { readLongTasks(browser, recorder) }
            recorder.addMainThreadCost(ns: MainLoopObserver.threadCPU() &- start)
        }
        let environment = ProcessInfo.processInfo.environment
        observeChanges(of: { [store = app.store] in store.settings.perfRecording }) { on in
            PerfRecorder.setRecording(PerfSessionRules.recording(setting: on, environment: environment))
        }
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

    /// Reads and resets the counters PageScript keeps in `__cra.lt`. A page without them (Cra's
    /// own pages, one still loading) answers null.
    private static let readLongTasksParams: String = {
        let js = "(() => { const l = window.__cra?.lt; if (!l || !l.n) return null; const r = JSON.stringify([l.n, l.t, l.d]); l.n = 0; l.t = 0; l.d = []; return r; })()"
        let params: [String: Any] = ["expression": js, "returnByValue": true]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: params)) ?? Data(), as: UTF8.self)
    }()

    private static func readLongTasks(_ browser: CraBrowser, _ recorder: PerfRecorder) {
        browser.evaluate(inIsolatedWorld: PageScript.world, params: readLongTasksParams) { [weak recorder] result, _ in
            guard let data = result?.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let value = (json["result"] as? [String: Any])?["value"] as? String,
                  let triple = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [Any], triple.count == 3,
                  let count = triple[0] as? Int, let total = triple[1] as? Double else { return }
            let durations = (triple[2] as? [Double]) ?? []
            DispatchQueue.main.async { recorder?.pageLongTasks(count: count, totalMs: total, durations: durations) }
        }
    }
}
