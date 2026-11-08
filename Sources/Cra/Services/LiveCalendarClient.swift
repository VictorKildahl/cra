import AppKit
import CraCEF

/// Arc's LiveCalendarClient for a Google Calendar favorite: a hidden page in the favorite's own
/// profile reads today's events (CalendarPreview.fetchScript), then closes ("Live Calendar
/// timeout reached; tearing down" after 25 s). The card, the tile's countdown and the Join link
/// read `state(for:)`; `changed` tells them when it moves.
@MainActor
final class LiveCalendarClient {
    static let shared = LiveCalendarClient()
    static let changed = Notification.Name("CraLiveCalendarChanged")

    struct State: Equatable {
        var events: [CalendarPreview.Event] = []
        var signedOut = false
        var failed = false
        var fetched: Date?
    }

    private(set) var states: [String: State] = [:]
    /// Meetings whose Join link was closed (CalendarPreview.key).
    private(set) var dismissed: Set<String> = []
    private var running: [String: HiddenPage] = [:]
    private var waiting: [String: [() -> Void]] = [:]
    private var timer: Timer?
    /// Calendar favorites seen lately (key → favorite URL and profile), refreshed by the timer.
    private var watched: [String: (favorite: String, profile: String?)] = [:]

    private static func key(_ embed: String, _ profile: String?) -> String { embed + "|" + (profile ?? "") }

    func state(for favorite: String, profilePath: String?) -> State? {
        CalendarPreview.embedURL(for: favorite).flatMap { states[Self.key($0, profilePath)] }
    }

    /// A Calendar favorite is in a sidebar: keep its events fresh (every 5 minutes, as the
    /// countdown and Join link need them without a hover).
    func watch(favorite: String, profilePath: String?) {
        guard let embed = CalendarPreview.embedURL(for: favorite) else { return }
        let k = Self.key(embed, profilePath)
        guard watched[k] == nil else { return }
        watched[k] = (favorite, profilePath)
        refresh(favorite: favorite, profilePath: profilePath, ifOlderThan: 60)
        if timer == nil {
            // Every 30 s the countdown and the Join link move on; every 5 min the events are read again.
            var ticks = 0
            let t = Timer(timeInterval: 30, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let s = LiveCalendarClient.shared
                    ticks += 1
                    if ticks % 10 == 0 { for w in s.watched.values { s.refresh(favorite: w.favorite, profilePath: w.profile) } }
                    NotificationCenter.default.post(name: LiveCalendarClient.changed, object: nil)
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    /// Arc's "Join next video conference" command: the call on now, else the next one today,
    /// from any watched Calendar favorite.
    func nextCall(now: Date = Date()) -> CalendarPreview.Event? {
        let all = watched.keys.compactMap { states[$0]?.events }.flatMap { $0 }
        return CalendarPreview.nextCall(in: all, now: now)
    }

    func dismiss(_ e: CalendarPreview.Event) {
        dismissed.insert(CalendarPreview.key(e))
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// Reads the favorite's calendar unless it was read within `age` seconds; `then` runs once
    /// there is an answer (or none in 25 s).
    func refresh(favorite: String, profilePath: String?, ifOlderThan age: TimeInterval = 0, then: (() -> Void)? = nil) {
        guard let embed = CalendarPreview.embedURL(for: favorite) else { then?(); return }
        let k = Self.key(embed, profilePath)
        if age > 0, let f = states[k]?.fetched, Date().timeIntervalSince(f) < age { then?(); return }
        if let then { waiting[k, default: []].append(then) }
        guard running[k] == nil else { return }
        let now = Date(), cal = Calendar.current
        let from = cal.startOfDay(for: now)
        let to = cal.date(byAdding: .day, value: 2, to: from) ?? now.addingTimeInterval(2 * 86400)
        CraLog.note("live calendar fetch begins (\(profilePath == nil ? "default profile" : "space profile"))")
        running[k] = HiddenPage(url: embed, profilePath: profilePath, script: CalendarPreview.fetchScript(from: from, to: to)) { [weak self] answer in
            self?.finish(k, answer.map(CalendarPreview.parse) ?? .failed)
        }
    }

    private func finish(_ k: String, _ fetch: CalendarPreview.Fetch) {
        running[k]?.close()
        running[k] = nil
        var s = states[k] ?? State()
        switch fetch {
        case .events(let events): s = State(events: events, fetched: Date())
        case .signedOut: s.signedOut = true; s.failed = false; s.events = []; s.fetched = Date()
        case .failed: s.failed = true
        }
        states[k] = s
        CraLog.note("live calendar fetch complete: \(s.signedOut ? "signed out" : s.failed ? "failed" : "\(s.events.count) events")")
        NotificationCenter.default.post(name: Self.changed, object: nil)
        for run in waiting.removeValue(forKey: k) ?? [] { run() }
    }

    /// Testing without a sign-in (cra://debug?calendarPreview=…): the events as if fetched.
    func setDemo(_ events: [CalendarPreview.Event], favorite: String, profilePath: String?) {
        guard let embed = CalendarPreview.embedURL(for: favorite) else { return }
        states[Self.key(embed, profilePath)] = State(events: events, fetched: Date())
        dismissed = []
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// A page no one sees: loads `url` in the profile, runs `script` (a promise of a string) once the
/// page committed, answers once, and is closed by its owner.
@MainActor
private final class HiddenPage: NSObject, @preconcurrency CraBrowserDelegate {
    private var browser: CraBrowser?
    private let script: String
    private var answer: ((String?) -> Void)?
    private var poll: Timer?

    init(url: String, profilePath: String?, script: String, answer: @escaping (String?) -> Void) {
        self.script = script
        self.answer = answer
        super.init()
        browser = CraBrowser(frame: NSRect(x: 0, y: 0, width: 800, height: 600), url: url, delegate: self, incognito: false, profilePath: profilePath)
        if let w = browser?.hostWindow { hide(w) }
        let started = Date()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let b = self.browser else { return }
                if Date().timeIntervalSince(started) > 25 { self.reply(nil); return }
                guard b.isCreated, b.hasCommittedLoad, !b.isLoading else { return }
                self.poll?.invalidate()
                self.poll = nil
                self.run(in: b)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func run(in b: CraBrowser) {
        let body = try? JSONSerialization.data(withJSONObject: ["expression": script, "awaitPromise": true, "returnByValue": true])
        b.sendDevToolsMethod("Runtime.evaluate", params: body.flatMap { String(data: $0, encoding: .utf8) } ?? "{}") { [weak self] result, _ in
            let value = result.flatMap { r -> String? in
                guard let json = try? JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any] else { return nil }
                return (json["result"] as? [String: Any])?["value"] as? String
            }
            DispatchQueue.main.async { self?.reply(value) }
        }
    }

    private func reply(_ value: String?) {
        poll?.invalidate()
        poll = nil
        let a = answer
        answer = nil
        a?(value)
    }

    func close() {
        poll?.invalidate()
        poll = nil
        answer = nil
        if let w = browser?.hostWindow { w.orderOut(nil) }
        browser?.close()
        browser = nil
    }

    private func hide(_ w: NSWindow) {
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.orderOut(nil)
    }

    func browser(_ browser: CraBrowser, didChangeTitle title: String) {}
    func browser(_ browser: CraBrowser, didChangeURL url: String) {}
    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {}
    func browser(_ browser: CraBrowser, didChangeProgress progress: Double) {}
    func browser(_ browser: CraBrowser, didFinishLoadingURL url: String, title: String, statusCode: Int) {}
    func browser(_ browser: CraBrowser, didLoadFavicon image: NSImage, forURL iconURL: String) {}
    func browser(_ browser: CraBrowser, didChangeStatusMessage message: String) {}
    func browser(_ browser: CraBrowser, didReportThemeColor hex: String) {}
    func browser(_ browser: CraBrowser, didChangeFullscreen fullscreen: Bool) {}
    func browser(_ browser: CraBrowser, requestsNewTabWithURL url: String, inBackground background: Bool) {}
    func browser(_ browser: CraBrowser, popupHostForURL url: String, inBackground background: Bool) -> CraBrowser? { nil }
    func devToolsHostView(for browser: CraBrowser) -> NSView? { nil }
    func browser(_ browser: CraBrowser, didCreateDevToolsView view: NSView) {}
    func browserDidCloseDevTools(_ browser: CraBrowser) {}
    func browser(_ browser: CraBrowser, didCreateHostWindow window: NSWindow) { hide(window) }
    func browser(_ browser: CraBrowser, devToolsPageBounds bounds: NSRect) {}
    func browser(_ browser: CraBrowser, devToolsDocked docked: Bool) {}
    func browser(_ browser: CraBrowser, handleKeyEvent event: NSEvent) -> Bool { false }
    func browser(_ browser: CraBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool { false }
    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) {}
    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void) { completion(false) }
    func browserDidReceiveFocus(_ browser: CraBrowser) {}
    func browserDidClose(_ browser: CraBrowser) {}
}
