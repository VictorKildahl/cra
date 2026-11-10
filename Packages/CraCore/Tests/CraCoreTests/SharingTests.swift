import CraCore
import Foundation
import Testing

/// Settings ▸ Privacy ▸ Sharing and onboarding's Privacy step: what Cra may send, when, and
/// what a report holds (docs/sharing.md).
struct SharingTests {
    // MARK: - Who may report

    struct Copy: Sendable, CustomTestStringConvertible {
        let feed: Bool, dataDir: Bool, bundle: String, override: Bool, may: Bool
        var testDescription: String { "\(bundle) feed=\(feed) dataDir=\(dataDir) override=\(override)" }
    }

    static let copies: [Copy] = [
        Copy(feed: true, dataDir: false, bundle: "dk.kildahl.cra", override: false, may: true),
        Copy(feed: false, dataDir: false, bundle: "dk.kildahl.cra", override: false, may: false),    // dev build: no SUFeedURL
        Copy(feed: true, dataDir: true, bundle: "dk.kildahl.cra", override: false, may: false),      // test copy on its own data folder
        Copy(feed: true, dataDir: false, bundle: "dk.kildahl.cra.dev", override: false, may: false), // renamed bundle
        Copy(feed: false, dataDir: true, bundle: "dk.kildahl.cra.test", override: true, may: true),  // CRA_SHARING_ENDPOINT: on purpose
    ]

    @Test(arguments: copies)
    func onlyTheReleasedAppReports(_ c: Copy) {
        #expect(Sharing.mayReport(hasUpdateFeed: c.feed, testDataFolder: c.dataDir, bundleID: c.bundle, endpointOverride: c.override) == c.may)
    }

    @Test func endpointsLiveOnCrabrowserApp() {
        #expect(Sharing.statsURL(base: nil).absoluteString == "https://crabrowser.app/api/stats")
        #expect(Sharing.crashURL(base: nil).absoluteString == "https://crabrowser.app/api/crash")
        #expect(Sharing.statsURL(base: "http://127.0.0.1:9999").absoluteString == "http://127.0.0.1:9999/api/stats")
        #expect(Sharing.crashURL(base: "http://127.0.0.1:9999/").absoluteString == "http://127.0.0.1:9999/api/crash")
    }

    // MARK: - Settings

    @Test func nothingIsSharedUntilTheUserSaysSo() throws {
        #expect(AppSettings().shareUsageStats == false)
        #expect(AppSettings().crashReports == .ask)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.shareUsageStats == false)
        #expect(old.crashReports == .ask)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"crashReports":"sometimes"}"#.utf8))
        #expect(unknown.crashReports == .ask)
    }

    @Test func eachMacMakesItsOwnChoice() {
        var mine = AppSettings()
        mine.shareUsageStats = true
        mine.crashReports = .send
        var other = AppSettings()
        other.crashReports = .never
        #expect(mine.forSync().shareUsageStats == false)
        #expect(mine.forSync().crashReports == .ask)
        let merged = mine.applyingSynced(other)
        #expect(merged.shareUsageStats == true)
        #expect(merged.crashReports == .send)
    }

    @Test func onboardingSharesBothOrNeither() {
        var s = AppSettings()
        s.setSharesToImproveCra(true)
        #expect(s.sharesToImproveCra)
        #expect(s.shareUsageStats && s.crashReports == .send)
        s.setSharesToImproveCra(false)
        #expect(!s.sharesToImproveCra)
        #expect(!s.shareUsageStats && s.crashReports == .ask)
        // Never asking stays never when the onboarding row is left off.
        s.crashReports = .never
        s.setSharesToImproveCra(false)
        #expect(s.crashReports == .never)
    }

    /// The sidebar's "Help improve Cra" card: on the released app, after onboarding, until the Mac
    /// has answered. People who updated from before 0.1.39 never saw onboarding's row.
    @Test func theSharingCardAsksUntilAnswered() throws {
        var s = AppSettings()
        #expect(SharingPrompt.shows(s, mayReport: true, onboarding: false))
        #expect(!SharingPrompt.shows(s, mayReport: false, onboarding: false), "dev builds and test copies don't ask")
        #expect(!SharingPrompt.shows(s, mayReport: true, onboarding: true), "onboarding asks itself")
        s.shareUsageStats = true
        #expect(!SharingPrompt.shows(s, mayReport: true, onboarding: false), "already sharing")
        s = AppSettings()
        s.askedToShare = true
        #expect(!SharingPrompt.shows(s, mayReport: true, onboarding: false), "answered")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!old.askedToShare, "settings from before the card haven't answered it")
    }

    @Test func answeringTheCardIsFinal() {
        var yes = AppSettings()
        yes.answerSharingPrompt(share: true)
        #expect(yes.shareUsageStats && yes.askedToShare)
        #expect(yes.crashReports == .ask, "the card is about usage stats; crash reports still ask")
        var no = AppSettings()
        no.answerSharingPrompt(share: false)
        #expect(!no.shareUsageStats && no.askedToShare)
    }

    @Test func eachMacAnswersTheCardItself() {
        var mine = AppSettings()
        mine.askedToShare = true
        #expect(mine.forSync().askedToShare == false)
        #expect(mine.applyingSynced(AppSettings()).askedToShare == true)
        #expect(AppSettings().applyingSynced(mine).askedToShare == false)
    }

    /// sharing.json loads as recorded, and a missing or empty one means nothing was sent yet.
    @Test func sharingFileLoadsAsRecorded() throws {
        let (loaded, recorded) = try ModelFixtureTests.load("sharing.json", as: SharingState.self)
        #expect(loaded == recorded)
        #expect(loaded.statsSentAt == ISO8601DateFormatter().date(from: "2026-11-09T08:30:00Z"))
        #expect(try ModelFixtureTests.roundTrips(loaded))
        #expect(try ModelFixtureTests.decoder.decode(SharingState.self, from: Data("{}".utf8)) == SharingState())
    }

    // MARK: - Usage stats

    /// One report per UTC day, so a day's reports count that day's users, per version.
    static let days: [(Double?, Double, Bool)] = [
        (nil, 0, true),
        (10, 86399, false),          // later the same UTC day
        (86399, 86400, true),        // a second later, but the next UTC day
        (0, 3 * 86400 + 5, true),
        (10 * 86400, 0, true),       // the clock went back: report rather than wait days
    ]

    @Test(arguments: days)
    func statsGoOutOnceADay(lastSent: Double?, now: Double, due: Bool) {
        #expect(UsageStats.isDue(lastSent: lastSent.map { Date(timeIntervalSince1970: $0) }, now: Date(timeIntervalSince1970: now)) == due)
    }

    static let buckets: [(Int, String)] = [(0, "0"), (1, "1"), (3, "2–3"), (5, "4–5"), (10, "6–10"), (20, "11–20"),
                                           (50, "21–50"), (100, "51–100"), (101, "101+"), (5000, "101+")]

    @Test(arguments: buckets)
    func countsAreRanges(count: Int, bucket: String) {
        #expect(UsageStats.bucket(count) == bucket)
    }

    @Test func everySettingIsSortedIntoReportedOrNot() throws {
        let keys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any]).keys
        let sorted = UsageStats.reportedSettings.union(UsageStats.unreportedSettings)
        // A new setting has to be put in one list or the other before it ships.
        #expect(Set(keys).subtracting(sorted).isEmpty, "unsorted: \(Set(keys).subtracting(sorted).sorted())")
        #expect(UsageStats.reportedSettings.isDisjoint(with: UsageStats.unreportedSettings))
        // autoArchiveDays is only written for thresholds longer than Arc's.
        #expect(sorted.subtracting(keys).subtracting(["autoArchiveDays"]).isEmpty, "not settings: \(sorted.subtracting(keys).sorted())")
    }

    @Test func onlyChangedSettingsAreReportedAndNeverText() {
        var s = AppSettings()
        #expect(UsageStats.changedSettings(s).isEmpty)
        s.blockCookieBanners = true
        s.tabSleepAfter = AppSettings().tabSleepAfter == .fourHours ? .oneHour : .fourHours
        s.developerHosts = ["intranet.example.com"]
        s.mediaHidden = ["/Users/someone/Movies/private.mov"]
        s.setDownloadLocation(DownloadLocation(folder: "/Users/someone/Secret", askWhereToSave: true), profileID: nil)
        let changed = UsageStats.changedSettings(s)
        #expect(changed["blockCookieBanners"] == "true")
        #expect(changed["tabSleepAfter"] != nil)
        #expect(changed.keys.allSatisfy { UsageStats.reportedSettings.contains($0) })
        let text = changed.values.joined(separator: " ")
        #expect(!text.contains("example.com") && !text.contains("/Users"))
    }

    @Test func aStatsReportHoldsRangesNotNumbersOrNames() throws {
        var settings = AppSettings()
        settings.httpsOnly = true
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let stats = UsageStats(id: id, version: "0.1.38", build: "202611100825",
                               os: OperatingSystemVersion(majorVersion: 26, minorVersion: 7, patchVersion: 1),
                               arch: "arm64", memoryBytes: 32 << 30, spaces: 4, profiles: 2, tabs: 37, extensions: 0,
                               settings: settings)
        let json = try #require(try JSONSerialization.jsonObject(with: stats.json()) as? [String: Any])
        #expect(Set(json.keys) == ["id", "version", "build", "macOS", "arch", "memoryGB", "spaces", "profiles", "tabs", "extensions", "settings"])
        #expect(json["id"] as? String == id.uuidString)
        #expect(json["macOS"] as? String == "26.7")
        #expect(json["memoryGB"] as? Int == 32)
        #expect(json["spaces"] as? String == "4–5")
        #expect(json["tabs"] as? String == "21–50")
        #expect(json["extensions"] as? String == "0")
        #expect(json["settings"] as? [String: String] == ["httpsOnly": "true"])
    }

    // MARK: - Crash reports

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theFirstLookOnlyMarksWhereToStart() {
        let files = [CrashReports.File(name: "Cra-2026-11-01-120000.ips", modified: t0.addingTimeInterval(-60))]
        let r = CrashReports.pending(files, seenUntil: nil, now: t0)
        #expect(r.send.isEmpty)
        #expect(r.seenUntil == t0)
    }

    @Test func newCraReportsAreFoundNewestFirstAtMostFive() {
        var files = (0..<7).map { CrashReports.File(name: "Cra Helper (Renderer)-\($0).ips", modified: t0.addingTimeInterval(Double($0 + 1))) }
        files.append(.init(name: "Craft-2026-11-01.ips", modified: t0.addingTimeInterval(30)))
        files.append(.init(name: "Cra-old.ips", modified: t0.addingTimeInterval(-1)))
        files.append(.init(name: "Cra-main.ips", modified: t0.addingTimeInterval(20)))
        files.append(.init(name: "Cra-notes.txt", modified: t0.addingTimeInterval(20)))
        let r = CrashReports.pending(files, seenUntil: t0, now: t0.addingTimeInterval(100))
        #expect(r.send == ["Cra-main.ips", "Cra Helper (Renderer)-6.ips", "Cra Helper (Renderer)-5.ips",
                           "Cra Helper (Renderer)-4.ips", "Cra Helper (Renderer)-3.ips"])
        #expect(r.seenUntil == t0.addingTimeInterval(100))
    }

    @Test func aMainProcessCrashIsCraQuitting() {
        #expect(CrashReports.isAppQuit("Cra-2026-11-10-120000.ips"))
        #expect(!CrashReports.isAppQuit("Cra Helper (GPU)-2026-11-10-120000.ips"))
    }

    private func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "Cra-2026-11-10-120000", withExtension: "ips", subdirectory: "Fixtures/Sharing"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func aCrashReportLeavesWithoutAnythingThatIdentifiesTheMacOrUser() throws {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let data = try #require(CrashReports.reduce(ips: try fixture(), id: id, home: "/Users/someone"))
        let text = String(decoding: data, as: UTF8.self)
        for marker in ["CRASH-REPORTER-KEY-MARKER", "SLEEP-WAKE-MARKER", "BOOT-SESSION-MARKER", "INCIDENT-ID-MARKER",
                       "VENDOR-ID-MARKER", "ROLLOUT-MARKER", "secretSelector", "someone", "secret.db", "inbox", "q=secret",
                       "\"userID\"", "\"path\"", "procPath", "parentProc", "responsibleProc", "threadState", "TEAMID"] {
            #expect(!text.contains(marker), "still holds \(marker)")
        }
    }

    @Test func aCrashReportKeepsWhatFindsTheBug() throws {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let data = try #require(CrashReports.reduce(ips: try fixture(), id: id, home: "/Users/someone"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["id"] as? String == id.uuidString)
        let header = try #require(json["header"] as? [String: Any])
        #expect(header["app_version"] as? String == "0.1.38")
        #expect(header["os_version"] as? String == "macOS 26.7.1 (25G241)")
        #expect(header["slice_uuid"] as? String == "11111111-2222-3333-4444-555555555555")
        let body = try #require(json["body"] as? [String: Any])
        #expect((body["exception"] as? [String: Any])?["type"] as? String == "EXC_BAD_ACCESS")
        #expect(body["faultingThread"] as? Int == 0)
        let threads = try #require(body["threads"] as? [[String: Any]])
        #expect(threads.count == 2)
        #expect(((threads[0]["frames"] as? [[String: Any]])?.first?["symbol"]) as? String == "CraBrowser::Close()")
        let images = try #require(body["usedImages"] as? [[String: Any]])
        #expect(images.map { $0["name"] as? String } == ["Chromium Embedded Framework", "Cra", "libsystem_kernel.dylib"])
        #expect(images[0]["uuid"] as? String == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        // The app's own message keeps the site, not the page, and the home folder becomes ~.
        let asi = try #require((body["asi"] as? [String: [String]])?["Cra"]?.first)
        #expect(asi == "loading https://mail.example.com/… from ~/Desktop")
    }

    /// A report from another user's home (or a home Cra was started with, CFFIXED_USER_HOME) still
    /// names no user: crabrowser.app refuses any report with /Users/ in it.
    @Test func anyUsersFolderIsCut() throws {
        let data = try #require(CrashReports.reduce(ips: try fixture(), id: UUID(), home: "/private/tmp/elsewhere"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("someone"))
        #expect(text.contains("from ~/Desktop"))
    }

    @Test func notACrashReportIsNothing() {
        #expect(CrashReports.reduce(ips: "hello", id: UUID(), home: "/Users/someone") == nil)
        #expect(CrashReports.reduce(ips: "{}\nnot json", id: UUID(), home: "/Users/someone") == nil)
    }

    @Test func aHugeReportKeepsOnlyTheCrashedThread() throws {
        var ips = try fixture()
        let filler = String(repeating: "x", count: 2000)
        let many = (0..<400).map { #"{"id":\#($0),"name":"\#(filler)","frames":[]}"# }.joined(separator: ",")
        ips = ips.replacingOccurrences(of: #"    {"id" : 7002"#, with: "    \(many),\n    {\"id\" : 7002")
        let data = try #require(CrashReports.reduce(ips: ips, id: UUID(), home: "/Users/someone"))
        #expect(data.count <= CrashReports.maxBytes)
        let body = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["body"] as? [String: Any])
        let threads = try #require(body["threads"] as? [[String: Any]])
        #expect(threads.count == 1)
        #expect(threads[0]["triggered"] as? Bool == true)
    }
}
