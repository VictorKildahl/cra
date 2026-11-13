import CraCore
import Foundation
import Testing

/// Arc's Outlook Mail, Outlook Calendar and Notion Calendar previews (GitHub #376), read with the
/// page's own sign-in.
struct OutlookPreviewTests {
    static let kinds: [(String, OutlookPreview.Kind?)] = [
        ("https://outlook.live.com/mail/0/", .mail),
        ("https://outlook.live.com/mail/0/inbox", .mail),
        ("https://outlook.office.com/mail/", .mail),
        ("https://outlook.office365.com/owa/", .mail),
        ("https://outlook.cloud.microsoft/mail/", .mail),
        ("https://outlook.live.com/calendar/0/view/day", .calendar),
        ("https://outlook.office.com/calendar/view/week", .calendar),
        ("https://outlook.live.com/people/0/", nil),
        ("https://outlook.com/", nil),
        ("http://outlook.live.com/mail/0/", nil),
        ("https://mail.google.com/mail/u/0/", nil),
    ]

    @Test(arguments: kinds)
    func knowsOutlooksPages(url: String, kind: OutlookPreview.Kind?) {
        #expect(OutlookPreview.kind(for: url) == kind)
    }

    /// Mail and calendar of one account share a reader; personal accounts are numbered as Gmail's are.
    @Test func oneReaderPerAccount() {
        #expect(OutlookPreview.account(for: "https://outlook.live.com/mail/0/inbox") == OutlookPreview.account(for: "https://outlook.live.com/calendar/0/view/day"))
        #expect(OutlookPreview.account(for: "https://outlook.live.com/mail/1/") != OutlookPreview.account(for: "https://outlook.live.com/mail/0/"))
        #expect(OutlookPreview.account(for: "https://outlook.office.com/calendar/view/week") == "outlook.office.com/")
        #expect(OutlookPreview.pageURL(for: "https://outlook.live.com/calendar/1/view/day") == "https://outlook.live.com/mail/1/")
        #expect(OutlookPreview.pageURL(for: "https://outlook.office.com/calendar/") == "https://outlook.office.com/mail/")
    }

    /// Arc's ＋ addresses (deeplink/compose), for the favorite's own Outlook.
    @Test func composeAndNewEvent() {
        #expect(OutlookPreview.composeURL(for: "https://outlook.live.com/mail/0/") == "https://outlook.live.com/mail/0/deeplink/compose")
        #expect(OutlookPreview.newEventURL(for: "https://outlook.live.com/calendar/0/") == "https://outlook.live.com/calendar/0/deeplink/compose")
        #expect(OutlookPreview.composeURL(for: "https://outlook.office.com/mail/") == "https://outlook.office.com/mail/deeplink/compose")
    }

    /// The sign-in comes from Outlook's own service requests and nothing else: other hosts,
    /// other paths and requests without one are ignored; the cookie never travels this way.
    @Test func takesTheSignInFromOutlooksOwnRequests() throws {
        let found = try #require(OutlookPreview.service(
            fromRequest: "https://outlook.live.com/owa/0/service.svc?action=FindConversation&app=Mail&n=12",
            headers: ["Authorization": "Bearer abc", "X-AnchorMailbox": "PUID:1@84df", "Cookie": "secret", "Action": "FindConversation"]))
        #expect(found.url == "https://outlook.live.com/owa/0/service.svc")
        #expect(found.headers == ["authorization": "Bearer abc", "x-anchormailbox": "PUID:1@84df"])
        #expect(OutlookPreview.service(fromRequest: "https://outlook.office.com/owa/startupdata.ashx?app=Mail", headers: ["x-owa-canary": "c"])?.url
            == "https://outlook.office.com/owa/service.svc")
        #expect(OutlookPreview.service(fromRequest: "https://outlook.live.com/owa/0/service.svc?action=X", headers: [:]) == nil)
        #expect(OutlookPreview.service(fromRequest: "https://evil.example/owa/service.svc", headers: ["Authorization": "Bearer abc"]) == nil)
        #expect(OutlookPreview.service(fromRequest: "https://outlook.live.com/mail/0/", headers: ["Authorization": "Bearer abc"]) == nil)
    }

    /// The script repeats only the sign-in headers, asks for unread inbox mail and the day's
    /// events, and puts `__type` first in every object, as the service needs.
    @Test func theScriptAsksForUnreadMailAndTheDay() {
        let from = Date(timeIntervalSince1970: 1_794_441_600)
        let s = OutlookPreview.fetchScript(service: "https://outlook.live.com/owa/0/service.svc", headers: ["authorization": "Bearer abc"],
                                           from: from, to: from.addingTimeInterval(2 * 86400))
        #expect(s.contains("\"authorization\":\"Bearer abc\""))
        #expect(s.contains("ViewFilter: 'Unread'") && s.contains("Id: 'inbox'"))
        #expect(s.contains("RangeStart: '2026-11-12T00:00:00Z', RangeEnd: '2026-11-14T00:00:00Z'"))
        #expect(s.contains("{ __type: T(action + 'JsonRequest'), Header"))
        #expect(s.contains("redirect: 'manual'"))
    }

    static let answer = """
    {"mail":{"Body":{"ResponseMessages":{"Items":[{"__type":"FindItemResponseMessage:#Exchange","ResponseClass":"Success","ResponseCode":"NoError",
      "RootFolder":{"TotalItemsInView":7,"IncludesLastItemInRange":false,"Items":[
        {"__type":"Message:#Exchange","ItemId":{"Id":"AAMk+a/b=","ChangeKey":"x"},"Subject":"Lunch & plans","DateTimeReceived":"2026-11-12T09:30:00Z",
         "From":{"Mailbox":{"Name":"Ada Lovelace","EmailAddress":"ada@example.com","RoutingType":"SMTP"}},"IsRead":false,"Preview":"Hi there,\\r\\n  lunch?"},
        {"__type":"Message:#Exchange","ItemId":{"Id":"AAMk2"},"Subject":"Invoice","DateTimeReceived":"2026-11-12T08:00:00Z",
         "From":{"Mailbox":{"Name":"","EmailAddress":"billing@example.com"}},"IsRead":false}]}}]}}},
     "calendar":{"Body":{"ResponseClass":"Success","Items":[
        {"__type":"CalendarItem:#Exchange","ItemId":{"Id":"EV2"},"Subject":"Review","Start":"2026-11-12T13:00:00Z","End":"2026-11-12T14:00:00Z",
         "Location":{"DisplayName":"Room 4"}},
        {"__type":"CalendarItem:#Exchange","ItemId":{"Id":"EV1"},"Subject":"Standup","Start":"2026-11-12T09:00:00Z","End":"2026-11-12T09:15:00Z",
         "Location":{"DisplayName":"Microsoft Teams Meeting"},"IsOnlineMeeting":true,"Preview":"Join: https://teams.microsoft.com/l/meetup-join/abc thanks"},
        {"__type":"CalendarItem:#Exchange","ItemId":{"Id":"EV3"},"Subject":"Gone","Start":"2026-11-12T15:00:00Z","End":"2026-11-12T16:00:00Z","IsCancelled":true}]}}}
    """

    @Test func readsTheUnreadMail() throws {
        guard case .read(let inbox, _) = OutlookPreview.parse(Self.answer, host: "outlook.live.com") else { Issue.record("not read"); return }
        #expect(inbox.unread == 7)
        #expect(inbox.mails.map(\.from) == ["Ada Lovelace", "billing@example.com"])
        #expect(inbox.mails.first?.subject == "Lunch & plans")
        #expect(inbox.mails.first?.snippet == "Hi there, lunch?")
        #expect(inbox.mails.first?.received == ISO8601DateFormatter().date(from: "2026-11-12T09:30:00Z"))
        #expect(inbox.mails.first?.link == "https://outlook.live.com/owa/?ItemID=AAMk%2Ba%2Fb%3D&exvsurl=1&viewmodel=ReadMessageItem")
    }

    @Test func readsTheDaysEventsInOrderWithTheirCalls() throws {
        guard case .read(_, let events) = OutlookPreview.parse(Self.answer, host: "outlook.office.com") else { Issue.record("not read"); return }
        #expect(events.map(\.title) == ["Standup", "Review"])
        #expect(events.first?.meetingURL == "https://teams.microsoft.com/l/meetup-join/abc")
        #expect(events.last?.meetingURL == nil)
        #expect(events.first?.link == "https://outlook.office.com/owa/?itemid=EV1&exvsurl=1&path=/calendar/item")
    }

    @Test func signInTroubleIsSignedOutAndAnythingElseFailed() {
        #expect(OutlookPreview.parse(#"{"status":401}"#, host: "outlook.live.com") == .signedOut)
        #expect(OutlookPreview.parse(#"{"status":440}"#, host: "outlook.live.com") == .signedOut)
        #expect(OutlookPreview.parse(#"{"status":500}"#, host: "outlook.live.com") == .failed)
        #expect(OutlookPreview.parse("nonsense", host: "outlook.live.com") == .failed)
        #expect(OutlookPreview.parse(#"{"mail":{"Body":{"ResponseMessages":{"Items":[{"ResponseClass":"Error"}]}}},"calendar":{}}"#, host: "outlook.live.com") == .failed)
        #expect(OutlookPreview.isSignIn("https://login.live.com/login.srf?wa=wsignin1.0"))
        #expect(OutlookPreview.isSignIn("https://login.microsoftonline.com/common/oauth2/authorize"))
        #expect(!OutlookPreview.isSignIn("https://outlook.live.com/mail/0/"))
    }

    @Test func notionCalendar() {
        #expect(NotionCalendarPreview.isNotionCalendar("https://calendar.notion.so/"))
        #expect(NotionCalendarPreview.isNotionCalendar("https://calendar.notion.com/week"))
        #expect(!NotionCalendarPreview.isNotionCalendar("https://www.notion.so/cra"))
        #expect(CalendarPreview.isCalendar(NotionCalendarPreview.googleCalendar))
    }

    /// Each behind its own checkbox, all on by default as in Arc; older settings.json load with them on.
    @Test func eachFollowsItsCheckbox() throws {
        var s = AppSettings()
        #expect(SidebarTabPreview.kind(for: "https://outlook.live.com/mail/0/", settings: s) == .outlookMail)
        #expect(SidebarTabPreview.kind(for: "https://outlook.office.com/calendar/", settings: s) == .outlookCalendar)
        #expect(SidebarTabPreview.kind(for: "https://calendar.notion.so/", settings: s) == .notionCalendar)
        s.outlookMailPreviews = false
        s.notionCalendarPreviews = false
        #expect(SidebarTabPreview.kind(for: "https://outlook.live.com/mail/0/", settings: s) == nil)
        #expect(SidebarTabPreview.kind(for: "https://outlook.live.com/calendar/0/", settings: s) == .outlookCalendar)
        #expect(SidebarTabPreview.kind(for: "https://calendar.notion.so/", settings: s) == nil)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(loaded.outlookMailPreviews && loaded.outlookCalendarPreviews && loaded.notionCalendarPreviews)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).outlookMailPreviews)
    }

    /// The gear's last item turns off that card's own preview.
    @Test func theGearTurnsOffItsOwnPreview() {
        var s = AppSettings()
        SidebarTabPreview.outlookCalendar.turnOff(&s)
        #expect(!s.outlookCalendarPreviews && s.liveCalendar && s.notionCalendarPreviews)
        SidebarTabPreview.calendar.turnOff(&s)
        #expect(!s.liveCalendar)
        #expect(SidebarTabPreview.calendar.turnOffTitle == "Disable Live Calendar")
        #expect(SidebarTabPreview.gmail.turnOffTitle == nil)
    }
}
