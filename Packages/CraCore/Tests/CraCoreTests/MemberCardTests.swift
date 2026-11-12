import CraCore
import Foundation
import Testing

/// Settings ▸ Sync's member card and "Share Cra with a Friend", Cra's take on Arc 1.172.2's Account tab (its
/// membership card and "Gift Arc to a Friend"), made from this Mac alone.
struct MemberCardTests {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func theNicknameIsTheSameEveryTimeForTheSameMember() {
        let a = MemberCard(fullName: "Victor Kildahl", since: Self.day(2026, 10, 25), now: Self.day(2026, 11, 12), calendar: Self.utc)
        let b = MemberCard(fullName: "Victor Kildahl", since: Self.day(2026, 10, 25), now: Self.day(2028, 1, 1), calendar: Self.utc)
        #expect(a.nickname == b.nickname, "the date the card is drawn doesn't change it")
        #expect(a.nickname.split(separator: " ").count == 2)
    }

    @Test func theNicknameIsAKnownValueSoAnUpdateDoesNotRenameAnyone() {
        // FNV-1a over the seed: pinned, so a change to the hash or the word lists shows up here.
        #expect(MemberCard.nickname(seed: "") == "Quiet Drifter")
    }

    @Test func eachMemberGetsOneOfTheThemesAndKeepsIt() {
        let themes = (0..<200).map { MemberCard.theme(seed: "member \($0)") }
        #expect(themes.allSatisfy { (0..<MemberCard.themeCount).contains($0) })
        #expect(Set(themes).count == MemberCard.themeCount, "every theme turns up")
        let a = MemberCard(fullName: "Ada", since: Self.day(2026, 10, 25), now: Self.day(2026, 11, 1), calendar: Self.utc)
        let b = MemberCard(fullName: "Ada", since: Self.day(2026, 10, 25), now: Self.day(2029, 1, 1), calendar: Self.utc)
        #expect(a.theme == b.theme)
    }

    @Test func differentMembersMostlyGetDifferentNicknames() {
        let names = (0..<200).map { MemberCard.nickname(seed: "member \($0)") }
        #expect(Set(names).count > 100)
    }

    @Test func theNameIsMacOSsFullNameTidied() {
        #expect(MemberCard.displayName("  Victor   Kildahl ") == "Victor Kildahl")
        #expect(MemberCard.displayName("") == "Cra Member")
        #expect(MemberCard.displayName("   ") == "Cra Member")
    }

    @Test func aMemberFromCrasFirstYearGetsTheEarlyStamp() {
        #expect(MemberCard.stamps(since: Self.day(2026, 10, 25), now: Self.day(2026, 11, 12), calendar: Self.utc) == [.early(year: 2026)])
        #expect(MemberCard.stamps(since: Self.day(2027, 3, 1), now: Self.day(2027, 3, 20), calendar: Self.utc) == [])
    }

    @Test func theFirstYearHasOneStampThatGrowsAtOneThreeAndSixMonths() {
        let since = Self.day(2026, 10, 25)
        func at(_ y: Int, _ m: Int, _ d: Int) -> [MemberCard.Stamp] { MemberCard.stamps(since: since, now: Self.day(y, m, d), calendar: Self.utc) }
        #expect(at(2026, 11, 24) == [.early(year: 2026)], "not a month yet")
        #expect(at(2026, 11, 25) == [.early(year: 2026), .months(1)])
        #expect(at(2027, 1, 24) == [.early(year: 2026), .months(1)], "two months: still the 1-month stamp")
        #expect(at(2027, 1, 25) == [.early(year: 2026), .months(3)])
        #expect(at(2027, 4, 25) == [.early(year: 2026), .months(6)])
        #expect(at(2027, 10, 24) == [.early(year: 2026), .months(6)], "the day before the anniversary")
        #expect(at(2027, 10, 25) == [.early(year: 2026), .anniversary(1)], "the year stamp takes the months stamp's place")
        // Someone who joins later has no early stamp, only the months.
        #expect(MemberCard.stamps(since: Self.day(2027, 3, 1), now: Self.day(2027, 6, 2), calendar: Self.utc) == [.months(3)])
    }

    @Test func eachFullYearAddsAnAnniversaryAndTheCardKeepsTheLastThree() {
        #expect(MemberCard.stamps(since: Self.day(2026, 10, 25), now: Self.day(2027, 10, 25), calendar: Self.utc) == [.early(year: 2026), .anniversary(1)])
        #expect(MemberCard.stamps(since: Self.day(2026, 10, 25), now: Self.day(2030, 1, 1), calendar: Self.utc) == [.anniversary(1), .anniversary(2), .anniversary(3)])
    }

    @Test func aClockBeforeTheJoinDateGivesNoAnniversary() {
        #expect(MemberCard.stamps(since: Self.day(2027, 5, 1), now: Self.day(2027, 1, 1), calendar: Self.utc) == [])
    }

    @Test func theSharedLinkIsTheSiteTaggedAsAShare() {
        #expect(ShareCra.link == "https://crabrowser.app/?utm_source=cra-app&utm_campaign=share")
        #expect(ShareCra.text.hasPrefix(ShareCra.message))
        #expect(ShareCra.text.hasSuffix(ShareCra.link))
    }
}
