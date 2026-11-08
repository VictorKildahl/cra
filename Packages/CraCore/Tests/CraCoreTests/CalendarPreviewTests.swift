import CraCore
import Foundation
import Testing

/// Arc's Live Calendar on a Google Calendar favorite, read through the Calendar embed's client.
struct CalendarPreviewTests {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func at(_ h: Int, _ m: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: h, minute: m))!
    }

    /// The answer Google gave the embed's client on 8 Nov 2026 (one Meet event), trimmed.
    static let answer = """
    {"items":[{"summary":"Cra preview test","start":{"dateTime":"2026-11-08T09:10:00+01:00"},"end":{"dateTime":"2026-11-08T09:30:00+01:00"},
    "hangoutLink":"https://meet.google.com/ope-ucwb-mfe","conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/ope-ucwb-mfe"}]},
    "htmlLink":"https://www.google.com/calendar/event?eid=abc"},
    {"summary":"Holiday","start":{"date":"2026-11-09"},"end":{"date":"2026-11-10"}},
    {"summary":"Declined","start":{"dateTime":"2026-11-08T12:00:00Z"},"end":{"dateTime":"2026-11-08T13:00:00Z"},"attendees":[{"self":true,"responseStatus":"declined"}]},
    {"status":"cancelled","summary":"Gone","start":{"dateTime":"2026-11-08T12:00:00Z"},"end":{"dateTime":"2026-11-08T13:00:00Z"}},
    {"summary":"Zoom sync","location":"https://us02web.zoom.us/j/123?pwd=x","start":{"dateTime":"2026-11-08T14:00:00Z"},"end":{"dateTime":"2026-11-08T14:30:00Z"}},
    {"start":{"dateTime":"2026-11-08T15:00:00Z"},"end":{"dateTime":"2026-11-08T15:15:00Z"},"description":"no call here, see https://example.com"}]}
    """

    @Test func readsTheEventsAndTheirCalls() throws {
        guard case .events(let events) = CalendarPreview.parse(Self.answer) else { Issue.record("no events"); return }
        #expect(events.map(\.title) == ["Cra preview test", "Holiday", "Zoom sync", "(No title)"])
        let meet = try #require(events.first)
        #expect(meet.start == Self.at(8, 10))
        #expect(meet.end == Self.at(8, 30))
        #expect(meet.meetingURL == "https://meet.google.com/ope-ucwb-mfe")
        #expect(meet.link == "https://www.google.com/calendar/event?eid=abc")
        #expect(events[1].allDay)
        #expect(events[2].meetingURL == "https://us02web.zoom.us/j/123?pwd=x")
        #expect(events[3].meetingURL == nil)
    }

    @Test func aSignedOutCalendarAsksToSignIn() {
        #expect(CalendarPreview.parse(#"{"error":"status","status":401}"#) == .signedOut)
        #expect(CalendarPreview.parse(#"{"error":"no client"}"#) == .failed)
        #expect(CalendarPreview.parse("not json") == .failed)
    }

    @Test(arguments: [("https://calendar.google.com/calendar/u/0/r", "https://calendar.google.com/calendar/u/0/embed"),
                      ("https://calendar.google.com/calendar/u/2/r/week", "https://calendar.google.com/calendar/u/2/embed"),
                      ("https://calendar.google.com/", "https://calendar.google.com/calendar/u/0/embed")])
    func theHiddenPageOfTheFavoritesAccount(favorite: String, embed: String) {
        #expect(CalendarPreview.embedURL(for: favorite) == embed)
        #expect(CalendarPreview.isCalendar(favorite))
    }

    @Test func otherSitesAreNoCalendar() {
        #expect(CalendarPreview.embedURL(for: "https://mail.google.com/mail/u/0/") == nil)
        #expect(!CalendarPreview.isCalendar("https://example.com/calendar"))
        #expect(CalendarPreview.newEventURL(for: "https://calendar.google.com/calendar/u/1/r") == "https://calendar.google.com/calendar/u/1/r/eventedit")
    }

    /// Arc's labels on 8 Nov 2026 read "8 AM" … "12 PM" … "1 PM" on a Mac with a 24-hour clock.
    @Test func hourLabelsLikeArc() {
        #expect([0, 8, 11, 12, 13, 23].map(CalendarPreview.hourLabel) == ["12 AM", "8 AM", "11 AM", "12 PM", "1 PM", "11 PM"])
    }

    @Test func theCardOpensAtTheCurrentHour() {
        let morning = CalendarPreview.initialScroll(now: Self.at(8, 32), calendar: Self.utc, hourHeight: 42)
        let midnight = CalendarPreview.initialScroll(now: Self.at(0, 5), calendar: Self.utc, hourHeight: 42)
        #expect(morning == 323)
        #expect(midnight == 0)
    }

    @Test func overlappingEventsShareTheRow() {
        let a = CalendarPreview.Event(title: "A", start: Self.at(9), end: Self.at(10))
        let b = CalendarPreview.Event(title: "B", start: Self.at(9, 30), end: Self.at(11))
        let c = CalendarPreview.Event(title: "C", start: Self.at(10), end: Self.at(10, 30))
        let d = CalendarPreview.Event(title: "D", start: Self.at(13), end: Self.at(13, 5))
        let allDay = CalendarPreview.Event(title: "Holiday", start: Self.at(0), end: Self.at(23), allDay: true)
        let placed = CalendarPreview.layout([d, c, b, a, allDay], day: Self.at(12), calendar: Self.utc, hourHeight: 42)
        #expect(placed.map(\.event.title) == ["A", "B", "C", "D"])
        #expect(placed.map(\.column) == [0, 1, 0, 0])
        #expect(placed.map(\.columns) == [2, 2, 2, 1])
        #expect(placed[0].top == 9 * 42 && placed[0].height == 42)
        #expect(placed[3].height == 18, "a five-minute event keeps a readable height")
    }

    static let meeting = CalendarPreview.Event(title: "Standup", start: at(9), end: at(9, 15), meetingURL: "https://meet.google.com/x")

    /// Arc's default is Two Minutes Before; the link stays until the meeting ends.
    @Test func theJoinLinkShowsAtTheChosenLead() {
        let events = [Self.meeting]
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(8, 57), timing: .twoMinutes) == nil)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(8, 58), timing: .twoMinutes) == Self.meeting)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(8, 55), timing: .fiveMinutes) == Self.meeting)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(8, 59), timing: .onStart) == nil)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(9, 14), timing: .onStart) == Self.meeting)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(9, 15), timing: .tenMinutes) == nil)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(9), timing: .never) == nil)
        #expect(CalendarPreview.meetingToJoin(in: events, now: Self.at(9), timing: .twoMinutes, dismissed: [CalendarPreview.key(Self.meeting)]) == nil)
    }

    @Test func theJoinCommandTakesTheCallOnNowElseTheNextToday() {
        let later = CalendarPreview.Event(title: "Review", start: Self.at(14), end: Self.at(15), meetingURL: "https://zoom.us/j/1")
        let tomorrow = CalendarPreview.Event(title: "Tomorrow", start: Self.at(9).addingTimeInterval(86400), end: Self.at(10).addingTimeInterval(86400), meetingURL: "https://zoom.us/j/2")
        #expect(CalendarPreview.nextCall(in: [later, Self.meeting], now: Self.at(9, 5), calendar: Self.utc) == Self.meeting)
        #expect(CalendarPreview.nextCall(in: [later, Self.meeting], now: Self.at(10), calendar: Self.utc) == later)
        #expect(CalendarPreview.nextCall(in: [tomorrow], now: Self.at(10), calendar: Self.utc) == nil)
    }

    @Test func theTileCountsDownToTheNextMeeting() {
        let lunch = CalendarPreview.Event(title: "Lunch", start: Self.at(12), end: Self.at(13))
        #expect(CalendarPreview.timeToNext(in: [Self.meeting, lunch], now: Self.at(8, 48)) == "12m")
        #expect(CalendarPreview.timeToNext(in: [Self.meeting, lunch], now: Self.at(9, 5)) == "Now")
        #expect(CalendarPreview.timeToNext(in: [Self.meeting, lunch], now: Self.at(10)) == nil, "lunch is two hours away")
        #expect(CalendarPreview.timeToNext(in: [Self.meeting, lunch], now: Self.at(11, 0)) == "60m")
    }

    @Test func theGearMenusLastFetch() {
        #expect(CalendarPreview.lastFetch(Self.at(9), now: Self.at(9, 0)) == "Last fetch: Just now")
        #expect(CalendarPreview.lastFetch(Self.at(9), now: Self.at(9, 5)) == "Last fetch: 5 min ago")
        #expect(CalendarPreview.lastFetch(nil, now: Self.at(9)) == "Last fetch: Never")
    }

    @Test func theScriptAsksForThePrimaryCalendar() {
        let js = CalendarPreview.fetchScript(from: Self.at(0), to: Self.at(23))
        #expect(js.contains("calendars/primary/events"))
        #expect(js.contains("2026-11-08T00:00:00Z"))
    }
}
