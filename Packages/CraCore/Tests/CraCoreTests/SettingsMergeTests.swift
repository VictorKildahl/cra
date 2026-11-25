import CraCore
import Foundation
import Testing

/// Settings from another Mac merged field by field with this Mac's changes since the bundle both had (X, Chris Coyier,
/// 25 Nov 2026: "Archive tabs after" set on one Mac came back as 12 hours from the other).
struct SettingsMergeTests {
    @Test func eachMacKeepsWhatItChanged() {
        var base = AppSettings()
        base.autoArchiveEnabled = true
        base.autoArchive = .twelveHours
        var local = base
        local.setAutoArchive(.never, profileID: nil, otherProfiles: [])
        var remote = base
        remote.warnBeforeQuitting = true
        let merged = SettingsMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.autoArchive(profileID: nil) == .never, "this Mac's change stays")
        #expect(merged.warnBeforeQuitting, "the other Mac's change comes")
    }

    @Test func aFieldBothChangedTakesTheOtherMacsLaterWrite() {
        let base = AppSettings()
        var local = base
        local.autoArchive = .sevenDays
        var remote = base
        remote.autoArchive = .thirtyDays
        #expect(SettingsMerge.merge(base: base, local: local, remote: remote).autoArchive == .thirtyDays)
    }

    @Test func aTimerPastArcsThirtyDaysMovesAsOneSetting() {
        // 90 days is saved as "thirtyDays" with autoArchiveDays 90 (#278): the two fields are one choice.
        let base = AppSettings()
        var local = base
        local.autoArchive = .ninetyDays
        var remote = base
        remote.autoArchive = .thirtyDays
        #expect(SettingsMerge.merge(base: base, local: local, remote: remote).autoArchive == .thirtyDays)
        #expect(SettingsMerge.merge(base: base, local: remote, remote: local).autoArchive == .ninetyDays)
    }

    @Test func aProfilesTimerChangedThereComesAndOneChangedHereStays() {
        let work = UUID(), school = UUID()
        let base = AppSettings()
        var local = base
        local.setAutoArchive(.after(.sevenDays), profileID: work, otherProfiles: [work, school])
        var remote = base
        remote.warnBeforeQuitting = true
        var merged = SettingsMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.autoArchive(profileID: work) == .after(.sevenDays))
        remote.setAutoArchive(.never, profileID: school, otherProfiles: [work, school])
        merged = SettingsMerge.merge(base: base, local: base, remote: remote)
        #expect(merged.autoArchive(profileID: school) == .never)
    }

    @Test func nothingChangedHereIsTheOtherMacsSettings() {
        let base = AppSettings()
        var remote = base
        remote.autoArchive = .ninetyDays
        remote.warnBeforeQuitting = true
        #expect(SettingsMerge.merge(base: base, local: base, remote: remote) == remote)
    }
}
