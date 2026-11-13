import AppKit
import CraCEF

/// Arc's Outlook Mail and Outlook Calendar previews with the page's own sign-in (GitHub #376;
/// CraCore OutlookPreview): a hidden page opens the account's Outlook in the favorite's profile,
/// the sign-in headers come from Outlook's own requests to its service, and the same service is
/// asked for the inbox's unread mail and the next two days' events in one go. A mail favorite and
/// a calendar favorite of one account share the answer. Nothing is kept but the answer.
@MainActor
final class OutlookClient {
    static let shared = OutlookClient()
    static let changed = Notification.Name("CraOutlookChanged")

    struct State: Equatable {
        var inbox: GmailPreview.Inbox?
        var events: [CalendarPreview.Event] = []
        var signedOut = false
        var failed = false
        var fetched: Date?
    }

    private(set) var states: [String: State] = [:]
    private var running: [String: HiddenPage] = [:]

    private static func key(_ favorite: String, _ profile: String?) -> String? {
        OutlookPreview.account(for: favorite).map { $0 + "|" + (profile ?? "") }
    }

    func state(for favorite: String, profilePath: String?) -> State? {
        Self.key(favorite, profilePath).flatMap { states[$0] }
    }

    /// Reads the favorite's account unless it was read within `age` seconds.
    func refresh(favorite: String, profilePath: String?, ifOlderThan age: TimeInterval = 0) {
        guard let k = Self.key(favorite, profilePath), let page = OutlookPreview.pageURL(for: favorite),
              let host = URLComponents(string: favorite)?.host?.lowercased() else { return }
        if age > 0, let f = states[k]?.fetched, Date().timeIntervalSince(f) < age { return }
        guard running[k] == nil else { return }
        let now = Date(), cal = Calendar.current
        let from = cal.startOfDay(for: now)
        let to = cal.date(byAdding: .day, value: 2, to: from) ?? now.addingTimeInterval(2 * 86400)
        CraLog.note("outlook fetch begins (\(profilePath == nil ? "default profile" : "space profile"))")
        running[k] = HiddenPage(url: page, profilePath: profilePath, watch: { url, headers in
            OutlookPreview.service(fromRequest: url, headers: headers).map {
                OutlookPreview.fetchScript(service: $0.url, headers: $0.headers, from: from, to: to)
            }
        }, isSignIn: OutlookPreview.isSignIn) { [weak self] answer in
            self?.finish(k, answer.map { OutlookPreview.parse($0, host: host) } ?? .failed)
        }
    }

    private func finish(_ k: String, _ fetch: OutlookPreview.Fetch) {
        running[k]?.close()
        running[k] = nil
        var s = states[k] ?? State()
        switch fetch {
        case .read(let inbox, let events): s = State(inbox: inbox, events: events, fetched: Date())
        case .signedOut: s = State(signedOut: true, fetched: Date())
        case .failed: s.failed = true
        }
        states[k] = s
        // Counts only: never a sender or a subject in the log.
        CraLog.note("outlook fetch complete: \(s.signedOut ? "signed out" : s.failed ? "failed" : "\(s.inbox?.mails.count ?? 0) mails, \(s.events.count) events")")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// Testing without a sign-in (cra://debug?outlookPreview=…): an answer as if read.
    func setDemo(_ state: State, favorite: String) {
        guard let k = Self.key(favorite, nil) else { return }
        states[k] = state
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
