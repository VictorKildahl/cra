import Foundation

/// Arc's Outlook Mail and Outlook Calendar previews (Previews Settings…, GitHub #376), read with
/// the page's own sign-in as Cra's Gmail and Google Calendar cards are: Arc signs in to Microsoft
/// Graph with its own app; Cra opens the favorite in a hidden page of the space's profile, takes
/// the sign-in headers from Outlook's own requests to its service (`/owa/service.svc`), and asks
/// the same service for the inbox's unread mail and today's events. Nothing is kept but the
/// answer. The service's request shapes are Outlook on the web's EWS-over-JSON (FindItem,
/// GetCalendarView), as documented by open-source Outlook clients.
public enum OutlookPreview {
    public enum Kind: Equatable, Sendable { case mail, calendar }

    /// Outlook on the web: personal (outlook.live.com, `/mail/0/`) and work or school.
    static let hosts: Set<String> = ["outlook.live.com", "outlook.office.com", "outlook.office365.com", "outlook.cloud.microsoft"]

    public static func kind(for url: String) -> Kind? {
        guard let u = URLComponents(string: url), u.scheme == "https", let host = u.host?.lowercased(), hosts.contains(host) else { return nil }
        let path = u.path.lowercased()
        if path == "/calendar" || path.hasPrefix("/calendar/") { return .calendar }
        if path.isEmpty || path == "/" || path == "/mail" || path.hasPrefix("/mail/") || path.hasPrefix("/owa") { return .mail }
        return nil
    }

    /// One reader per account: the host and, for personal accounts, the account's number.
    public static func account(for favorite: String) -> String? {
        guard kind(for: favorite) != nil, let u = URLComponents(string: favorite), let host = u.host?.lowercased() else { return nil }
        return host + "/" + accountNumber(u)
    }

    private static func accountNumber(_ u: URLComponents) -> String {
        let parts = u.path.split(separator: "/").map(String.init)
        if parts.count > 1, ["mail", "calendar"].contains(parts[0].lowercased()), Int(parts[1]) != nil { return parts[1] }
        return u.host?.lowercased() == "outlook.live.com" ? "0" : ""
    }

    private static func base(_ favorite: String) -> (host: String, account: String)? {
        guard let u = URLComponents(string: favorite), let host = u.host?.lowercased(), hosts.contains(host) else { return nil }
        return (host, accountNumber(u))
    }

    /// The page the reader loads: the account's mail (its service answers mail and calendar alike).
    public static func pageURL(for favorite: String) -> String? {
        guard let (host, n) = base(favorite) else { return nil }
        return "https://\(host)/mail/" + (n.isEmpty ? "" : n + "/")
    }

    /// Arc's ＋ on the mail card and on the calendar card (deeplink/compose).
    public static func composeURL(for favorite: String) -> String? {
        guard let (host, n) = base(favorite) else { return nil }
        return "https://\(host)/mail/" + (n.isEmpty ? "" : n + "/") + "deeplink/compose"
    }

    public static func newEventURL(for favorite: String) -> String? {
        guard let (host, n) = base(favorite) else { return nil }
        return "https://\(host)/calendar/" + (n.isEmpty ? "" : n + "/") + "deeplink/compose"
    }

    /// A mail or event in Outlook on the web (the form Microsoft Graph gives as `webLink`).
    static func itemURL(host: String, id: String, event: Bool) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let enc = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        return event ? "https://\(host)/owa/?itemid=\(enc)&exvsurl=1&path=/calendar/item"
            : "https://\(host)/owa/?ItemID=\(enc)&exvsurl=1&viewmodel=ReadMessageItem"
    }

    /// Microsoft's sign-in pages, or Outlook's page for people who aren't signed in: the reader
    /// stops and the card offers to sign in.
    public static func isSignIn(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return ["login.live.com", "login.microsoftonline.com", "login.microsoft.com", "signup.live.com", "www.microsoft.com"].contains(host)
    }

    /// The headers Outlook's own requests carry that the reader repeats: the sign-in (a bearer
    /// token, or the older canary) and the mailbox they go to.
    public static let copiedHeaders: Set<String> = ["authorization", "x-anchormailbox", "x-owa-canary", "x-owa-sessionid"]

    /// Outlook's service, from one of its requests the page made, with the headers to repeat;
    /// nil for any other request, or one that carries no sign-in.
    public static func service(fromRequest url: String, headers: [String: String]) -> (url: String, headers: [String: String])? {
        guard var u = URLComponents(string: url), u.scheme == "https", let host = u.host?.lowercased(), hosts.contains(host) else { return nil }
        let path = u.path
        guard let r = path.range(of: "/service.svc", options: .caseInsensitive) ?? path.range(of: "/startupdata.ashx", options: .caseInsensitive),
              path.lowercased().contains("/owa/") else { return nil }
        u.path = String(path[..<r.lowerBound]) + "/service.svc"
        u.query = nil
        u.fragment = nil
        var kept: [String: String] = [:]
        for (k, v) in headers where copiedHeaders.contains(k.lowercased()) { kept[k.lowercased()] = v }
        guard kept["authorization"] != nil || kept["x-owa-canary"] != nil, let s = u.string else { return nil }
        return (s, kept)
    }

    /// The page's script: the inbox's unread mail, newest first (at most 20, as Gmail's feed), and
    /// the events from `from` to `to`, as one JSON string `{"mail":…,"calendar":…}` (or
    /// `{"status":401}` when the sign-in is no good).
    public static func fetchScript(service: String, headers: [String: String], from: Date, to: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        let h = (try? JSONSerialization.data(withJSONObject: headers, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let s = (try? JSONSerialization.data(withJSONObject: [service], options: [])).map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return """
        (async () => {
          const service = \(s)[0], signIn = \(h);
          const T = n => n + ':#Exchange';
          const header = { __type: T('JsonRequestHeaders'), RequestServerVersion: 'V2018_01_08',
            TimeZoneContext: { __type: T('TimeZoneContext'), TimeZoneDefinition: { __type: T('TimeZoneDefinitionType'), Id: 'UTC' } } };
          const call = async (action, body) => {
            const r = await fetch(service + '?action=' + action + '&app=Mail', { method: 'POST', credentials: 'include', redirect: 'manual',
              headers: Object.assign({ 'Action': action, 'Content-Type': 'application/json; charset=utf-8',
                'Prefer': 'IdType="ImmutableId", exchange.behavior="IncludeThirdPartyOnlineMeetingProviders"' }, signIn),
              body: JSON.stringify({ __type: T(action + 'JsonRequest'), Header: header, Body: Object.assign({ __type: T(action + 'Request') }, body) }) });
            if (r.status !== 200) throw r.status || 401;
            return r.json();
          };
          const prop = p => ({ __type: T('PropertyUri'), FieldURI: p });
          try {
            const mail = await call('FindItem', {
              ItemShape: { __type: T('ItemResponseShape'), BaseShape: 'IdOnly',
                AdditionalProperties: ['item:Subject', 'message:From', 'item:DateTimeReceived', 'message:IsRead', 'item:Preview'].map(prop) },
              ParentFolderIds: [{ __type: T('DistinguishedFolderId'), Id: 'inbox' }],
              Traversal: 'Shallow',
              Paging: { __type: T('IndexedPageView'), BasePoint: 'Beginning', Offset: 0, MaxEntriesReturned: 20 },
              ViewFilter: 'Unread',
              SortOrder: [{ __type: T('SortResults'), Order: 'Descending', Path: prop('item:DateTimeReceived') }] });
            const calendar = await call('GetCalendarView', {
              CalendarId: { __type: T('TargetFolderId'), BaseFolderId: { __type: T('DistinguishedFolderId'), Id: 'calendar' } },
              RangeStart: '\(f.string(from: from))', RangeEnd: '\(f.string(from: to))' });
            return JSON.stringify({ mail, calendar });
          } catch (e) { return JSON.stringify({ status: typeof e === 'number' ? e : 0 }); }
        })()
        """
    }

    public enum Fetch: Equatable, Sendable {
        case read(inbox: GmailPreview.Inbox, events: [CalendarPreview.Event])
        case signedOut
        case failed
    }

    /// The script's answer: links point at `host`, the favorite's Outlook.
    public static func parse(_ json: String, host: String) -> Fetch {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return .failed }
        if let status = root["status"] as? Int { return [401, 403, 440].contains(status) ? .signedOut : .failed }
        guard let mail = root["mail"] as? [String: Any], let calendar = root["calendar"] as? [String: Any] else { return .failed }
        let found = ((mail["Body"] as? [String: Any])?["ResponseMessages"] as? [String: Any])?["Items"] as? [[String: Any]]
        guard let first = found?.first, first["ResponseClass"] as? String != "Error" else { return .failed }
        let folder = first["RootFolder"] as? [String: Any] ?? [:]
        let mails = (folder["Items"] as? [[String: Any]] ?? []).map { item -> GmailPreview.Mail in
            let from = (item["From"] as? [String: Any]).flatMap { ($0["Mailbox"] as? [String: Any]) ?? $0 } ?? [:]
            let name = (from["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? from["EmailAddress"] as? String ?? ""
            return GmailPreview.Mail(from: name, subject: item["Subject"] as? String ?? "",
                                     snippet: (item["Preview"] as? String ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " "),
                                     received: (item["DateTimeReceived"] as? String).flatMap(date),
                                     link: ((item["ItemId"] as? [String: Any])?["Id"] as? String).map { itemURL(host: host, id: $0, event: false) })
        }
        let unread = folder["TotalItemsInView"] as? Int ?? mails.count
        let items = (calendar["Body"] as? [String: Any])?["Items"] as? [[String: Any]] ?? []
        let events = items.compactMap { event($0, host: host) }.sorted { $0.start < $1.start }
        return .read(inbox: GmailPreview.Inbox(unread: unread, mails: mails), events: events)
    }

    private static func event(_ item: [String: Any], host: String) -> CalendarPreview.Event? {
        guard item["IsCancelled"] as? Bool != true, let start = (item["Start"] as? String).flatMap(date),
              let end = (item["End"] as? String).flatMap(date) else { return nil }
        let location = (item["Location"] as? String) ?? ((item["Location"] as? [String: Any])?["DisplayName"] as? String) ?? ""
        let online = (item["OnlineMeetingJoinUrl"] as? String) ?? ((item["OnlineMeeting"] as? [String: Any])?["JoinUrl"] as? String)
        let meeting = online ?? CalendarPreview.meetingAddress(in: location + " " + (item["Preview"] as? String ?? ""))
        let title = (item["Subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(No title)"
        return CalendarPreview.Event(title: title, start: start, end: end, allDay: item["IsAllDayEvent"] as? Bool ?? false, meetingURL: meeting,
                                     link: ((item["ItemId"] as? [String: Any])?["Id"] as? String).map { itemURL(host: host, id: $0, event: true) })
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

/// Arc's Notion Calendar preview (GitHub #376): Notion Calendar shows the Google calendars it is
/// signed in to, and Arc 1.172.2 has no Notion reader (its binary only knows Notion Calendar's
/// hosts and its new-event page), so the card is Google Calendar's, read from the profile's
/// Google sign-in, with Notion Calendar's ＋.
public enum NotionCalendarPreview {
    public static func isNotionCalendar(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return host == "calendar.notion.so" || host == "calendar.notion.com"
    }

    /// The Google calendar Cra reads for it: the profile's first Google account.
    public static let googleCalendar = "https://calendar.google.com/calendar/u/0/r"
    /// Arc's ＋.
    public static let newEventURL = "https://calendar.notion.so/event/create"
}
