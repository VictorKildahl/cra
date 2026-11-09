import Foundation

/// Arc's Live Calendar for a Google Calendar favorite (Arc 1.172.1, Victor's signed-in Arc, 8 Nov
/// 2026): hovering the tile shows today as a timeline card, the tile counts down to the next
/// meeting, and a link to join it shows shortly before it starts. Arc reads the calendar with a
/// hidden page (its LiveCalendarClient); in 1.172.1 that page no longer reads and Arc says
/// "Failed to update", so Cra reads the events the way Google's own Calendar embed does: a hidden
/// `calendar.google.com/calendar/u/<n>/embed` page asks the Calendar API through the page's own
/// signed-in client (`gapi.client`) for the primary calendar. Nothing leaves the Mac but that
/// request to Google, made by the space's own sign-in.
public enum CalendarPreview {
    public struct Event: Equatable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date
        public var allDay: Bool
        /// The video call to join (Meet, Zoom, Teams…), when the event has one.
        public var meetingURL: String?
        /// The event in Google Calendar.
        public var link: String?

        public init(title: String, start: Date, end: Date, allDay: Bool = false, meetingURL: String? = nil, link: String? = nil) {
            (self.title, self.start, self.end, self.allDay, self.meetingURL, self.link) = (title, start, end, allDay, meetingURL, link)
        }
    }

    public enum Fetch: Equatable, Sendable {
        case events([Event])
        /// The calendar answered that nobody is signed in (Arc's CalendarPreviewLoginView).
        case signedOut
        case failed
    }

    // MARK: The favorite

    public static func isCalendar(_ url: String) -> Bool {
        URL(string: url)?.host == "calendar.google.com"
    }

    /// The hidden page for the favorite's account (u/0 unless the favorite names another).
    public static func embedURL(for favorite: String) -> String? {
        guard let u = URL(string: favorite), u.host == "calendar.google.com" else { return nil }
        let parts = u.path.split(separator: "/")
        let account = parts.firstIndex(of: "u").flatMap { parts.indices.contains($0 + 1) ? String(parts[$0 + 1]) : nil } ?? "0"
        return "https://calendar.google.com/calendar/u/\(account)/embed"
    }

    /// Arc's ＋ on the card: a new event in the favorite's account.
    public static func newEventURL(for favorite: String) -> String? {
        embedURL(for: favorite).map { $0.replacingOccurrences(of: "/embed", with: "/r/eventedit") }
    }

    // MARK: Reading

    /// Run in the hidden embed page (awaits a promise, returns a JSON string): today and tomorrow
    /// of the primary calendar, once the page's client is ready.
    public static func fetchScript(from: Date, to: Date) -> String {
        let iso = ISO8601DateFormatter()
        return """
            new Promise(done => {
              const started = Date.now();
              const ask = () => {
                const c = window.gapi && gapi.client && gapi.client.request;
                if (!c) { if (Date.now() - started > 15000) done(JSON.stringify({error: 'no client'})); else setTimeout(ask, 100); return; }
                gapi.client.request({path: 'https://clients6.google.com/calendar/v3/calendars/primary/events',
                  params: {singleEvents: true, orderBy: 'startTime', maxResults: 100, timeMin: '\(iso.string(from: from))', timeMax: '\(iso.string(from: to))'}})
                  .then(r => done(JSON.stringify({items: r.result.items || []})),
                        e => done(JSON.stringify({error: 'status', status: (e && e.status) || 0})));
              };
              ask();
            })
            """
    }

    /// The script's answer. 401/403 mean the space isn't signed in to Google.
    public static func parse(_ json: String) -> Fetch {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return .failed }
        if object["error"] != nil {
            let status = object["status"] as? Int ?? 0
            return status == 401 || status == 403 ? .signedOut : .failed
        }
        guard let items = object["items"] as? [[String: Any]] else { return .failed }
        return .events(items.compactMap(event))
    }

    private static func event(_ item: [String: Any]) -> Event? {
        if item["status"] as? String == "cancelled" { return nil }
        // Declined invitations stay off the card, as in Google Calendar's own day view.
        if let people = item["attendees"] as? [[String: Any]],
           people.contains(where: { $0["self"] as? Bool == true && $0["responseStatus"] as? String == "declined" }) { return nil }
        guard let start = item["start"] as? [String: Any], let end = item["end"] as? [String: Any] else { return nil }
        let allDay = start["date"] != nil
        guard let s = time(start), let e = time(end) else { return nil }
        return Event(title: (item["summary"] as? String) ?? "(No title)", start: s, end: max(e, s), allDay: allDay,
                     meetingURL: meetingURL(in: item), link: item["htmlLink"] as? String)
    }

    private static func time(_ field: [String: Any]) -> Date? {
        if let s = field["dateTime"] as? String { return ISO8601DateFormatter().date(from: s) }
        if let s = field["date"] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s)
        }
        return nil
    }

    /// The call: the event's Meet link, its conference's video entry, else a known meeting
    /// address in its location or notes.
    static func meetingURL(in item: [String: Any]) -> String? {
        if let meet = item["hangoutLink"] as? String { return meet }
        if let points = (item["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]],
           let video = points.first(where: { $0["entryPointType"] as? String == "video" })?["uri"] as? String { return video }
        for text in [item["location"], item["description"]].compactMap({ $0 as? String }) {
            if let url = meetingAddress(in: text) { return url }
        }
        return nil
    }

    private static let meetingHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com", "webex.com", "around.co"]

    static func meetingAddress(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let host = url.host?.lowercased(), url.scheme?.hasPrefix("http") == true else { continue }
            if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url.absoluteString }
        }
        return nil
    }

    // MARK: The card

    /// Arc's hour labels ("8 AM", "12 PM"), in English whatever the Mac's clock says.
    public static func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour % 24 < 12 ? "AM" : "PM")"
    }

    /// Where the card scrolls to: the current hour's line 13 pt under the top, as in Arc.
    public static func initialScroll(now: Date, calendar: Calendar = .current, hourHeight: CGFloat) -> CGFloat {
        let hour = calendar.component(.hour, from: now)
        return max(0, CGFloat(hour) * hourHeight - 13)
    }

    /// A timed event on the day's timeline: points from the top of midnight, its width share and
    /// column (Arc's CalendarLayout: events that overlap share the row side by side).
    public struct Placement: Equatable, Sendable {
        public var event: Event
        public var top: CGFloat
        public var height: CGFloat
        public var column: Int
        public var columns: Int
    }

    public static func layout(_ events: [Event], day: Date, calendar: Calendar = .current, hourHeight: CGFloat, minHeight: CGFloat = 18) -> [Placement] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let timed = events.filter { !$0.allDay && $0.end > dayStart && $0.start < dayEnd }
            .sorted { ($0.start, $1.end) < ($1.start, $0.end) }
        func y(_ d: Date) -> CGFloat { CGFloat(min(max(d, dayStart), dayEnd).timeIntervalSince(dayStart) / 3600) * hourHeight }

        var out: [Placement] = []
        var group: [Placement] = []
        var groupEnd: CGFloat = -1
        var columnEnds: [CGFloat] = []
        func close() {
            let n = columnEnds.count
            out += group.map { var p = $0; p.columns = n; return p }
            group = []; columnEnds = []
        }
        for e in timed {
            let top = y(e.start), height = max(minHeight, y(e.end) - top)
            if top >= groupEnd { close() }
            let column = columnEnds.firstIndex { $0 <= top } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(top + height) } else { columnEnds[column] = top + height }
            group.append(Placement(event: e, top: top, height: height, column: column, columns: 1))
            groupEnd = max(groupEnd, top + height)
        }
        close()
        return out
    }

    // MARK: Meetings

    /// Arc's Show Next Meeting Link (Never, On Start, Two Minutes Before (its default), Five, Ten).
    public enum LinkTiming: String, Codable, CaseIterable, Sendable {
        case never, onStart, twoMinutes, fiveMinutes, tenMinutes

        public var title: String {
            switch self {
            case .never: return "Never"
            case .onStart: return "On Start"
            case .twoMinutes: return "Two Minutes Before"
            case .fiveMinutes: return "Five Minutes Before"
            case .tenMinutes: return "Ten Minutes Before"
            }
        }

        public var lead: TimeInterval? {
            switch self {
            case .never: return nil
            case .onStart: return 0
            case .twoMinutes: return 120
            case .fiveMinutes: return 300
            case .tenMinutes: return 600
            }
        }
    }

    /// The meeting whose link shows now: the soonest call that starts within the lead time and
    /// hasn't ended, skipping ones the person dismissed.
    public static func meetingToJoin(in events: [Event], now: Date, timing: LinkTiming, dismissed: Set<String> = []) -> Event? {
        guard let lead = timing.lead else { return nil }
        return events.filter { $0.meetingURL != nil && !$0.allDay && !dismissed.contains(key($0)) }
            .filter { now >= $0.start.addingTimeInterval(-lead) && now < $0.end }
            .min { $0.start < $1.start }
    }

    /// For the Join command: the call that is on now, else the next one today.
    public static func nextCall(in events: [Event], now: Date, calendar: Calendar = .current) -> Event? {
        let calls = events.filter { $0.meetingURL != nil && !$0.allDay && $0.end > now }
        if let current = calls.filter({ $0.start <= now }).min(by: { $0.start < $1.start }) { return current }
        return calls.filter { calendar.isDate($0.start, inSameDayAs: now) }.min { $0.start < $1.start }
    }

    /// Show Time to Next Meeting: the tile's countdown to the next timed event within the hour
    /// ("12m", "Now" while it runs), nil when none is near.
    public static func timeToNext(in events: [Event], now: Date) -> String? {
        let timed = events.filter { !$0.allDay && $0.end > now }
        if timed.contains(where: { $0.start <= now && $0.meetingURL != nil }) { return "Now" }
        guard let next = timed.filter({ $0.start > now }).min(by: { $0.start < $1.start }) else { return nil }
        let minutes = Int(ceil(next.start.timeIntervalSince(now) / 60))
        return minutes <= 60 ? "\(minutes)m" : nil
    }

    /// Identifies an event for dismissal (title and start).
    public static func key(_ e: Event) -> String { "\(e.title)|\(e.start.timeIntervalSince1970)" }

    /// "9:10 – 9:30" in the Mac's own clock style.
    public static func timeRange(_ e: Event, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeStyle = .short
        f.dateStyle = .none
        return "\(f.string(from: e.start)) – \(f.string(from: e.end))"
    }

    /// The gear menu's "Last fetch: …" line ("Just now", "5 min ago").
    public static func lastFetch(_ date: Date?, now: Date) -> String {
        guard let date else { return "Last fetch: Never" }
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "Last fetch: Just now" }
        if s < 3600 { return "Last fetch: \(s / 60) min ago" }
        return "Last fetch: \(s / 3600) h ago"
    }
}
