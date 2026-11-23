import CraCore
import Foundation
import Testing

/// Arc's per-profile "Archive tabs after" (Settings ▸ Profiles, GitHub #693): a work profile keeps its
/// tabs for 7 days while another archives after 12 hours.
struct ProfileAutoArchiveTests {
    static let work = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let school = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/693"))
    func eachProfileKeepsItsOwnTimer() {
        var s = AppSettings()
        s.setAutoArchive(.after(.sevenDays), profileID: Self.work, otherProfiles: [Self.work, Self.school])
        s.setAutoArchive(.never, profileID: Self.school, otherProfiles: [Self.work, Self.school])
        #expect(s.autoArchive(profileID: Self.work) == .after(.sevenDays))
        #expect(s.autoArchive(profileID: Self.school) == .never)
        // Default is the setting every Cra had: older ones still read it.
        #expect(s.autoArchive(profileID: nil) == .after(.twelveHours))
        #expect(s.autoArchive == .twelveHours && s.autoArchiveEnabled)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/693"))
    func aProfileNeverSetArchivesAsBeforeAndDefaultsChangeLeavesIt() {
        // Before #693 one timer served every profile: a profile never set keeps it after the update.
        var s = AppSettings()
        s.autoArchive = .sevenDays
        #expect(s.autoArchive(profileID: Self.work) == .after(.sevenDays))
        // Changing Default's then doesn't change the profiles' timers under them.
        s.setAutoArchive(.after(.twentyFourHours), profileID: nil, otherProfiles: [Self.work, Self.school])
        #expect(s.autoArchive(profileID: nil) == .after(.twentyFourHours))
        #expect(s.autoArchive(profileID: Self.work) == .after(.sevenDays))
        #expect(s.autoArchive(profileID: Self.school) == .after(.sevenDays))
        s.setAutoArchive(.never, profileID: nil, otherProfiles: [Self.work])
        #expect(!s.autoArchiveEnabled && s.autoArchive == .twentyFourHours)
        #expect(s.autoArchive(profileID: Self.work) == .after(.sevenDays))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/693"))
    func theTimersSurviveTheFileAndAnUnknownOneArchivesLater() throws {
        var s = AppSettings()
        s.setAutoArchive(.after(.ninetyDays), profileID: Self.work, otherProfiles: [Self.work])
        s.setAutoArchive(.never, profileID: Self.school, otherProfiles: [Self.work, Self.school])
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(loaded.autoArchive(profileID: Self.work) == .after(.ninetyDays))
        #expect(loaded.autoArchive(profileID: Self.school) == .never)
        // A value from a newer Cra: the longest timer this one knows, never sooner than asked.
        let json = #"{"profileAutoArchive": {"\#(Self.work.uuidString)": "oneYear"}}"#
        let newer = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(newer.autoArchive(profileID: Self.work) == .after(.oneHundredEightyDays))
        // A broken map leaves the rest of settings.json alone.
        let broken = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"profileAutoArchive": 3, "autoArchive": "sevenDays"}"#.utf8))
        #expect(broken.autoArchive(profileID: Self.work) == .after(.sevenDays))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/693"))
    func dueTabsFollowTheirSpacesTimer() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let old = now.addingTimeInterval(-2 * 86400), older = now.addingTimeInterval(-10 * 86400)
        let a = UUID(), b = UUID(), c = UUID()
        let tabs = [AutoArchive.Tab(id: a, lastActive: old), AutoArchive.Tab(id: b, lastActive: older), AutoArchive.Tab(id: c, lastActive: older)]
        // 7 days: only the tab idle for 10; the selected one stays whatever its age.
        #expect(AutoArchive.due(tabs, selected: [c], choice: .after(.sevenDays), now: now) == [b])
        #expect(AutoArchive.due(tabs, selected: [], choice: .after(.twelveHours), now: now) == [a, b, c])
        #expect(AutoArchive.due(tabs, selected: [], choice: .never, now: now).isEmpty)
    }
}
