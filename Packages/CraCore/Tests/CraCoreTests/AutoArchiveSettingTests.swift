import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ Tab Cleanup goes past Arc's 30 days to 90 and 180 (#278), without a
/// settings.json that an older Cra sets aside as corrupt.
struct AutoArchiveSettingTests {
    static func decode(_ json: String) throws -> AppSettings {
        try ModelFixtureTests.decoder.decode(AppSettings.self, from: Data(json.utf8))
    }

    static func saved(_ settings: AppSettings) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: ModelFixtureTests.encoder.encode(settings)) as? [String: Any])
    }

    /// AppSettings' autoArchive and searchEngine as Cra 0.1.36 and older decode them: a value they
    /// don't know throws, and JSONStore then moves the whole settings.json aside.
    struct OlderCraSettings: Decodable {
        enum Threshold: String, Decodable { case twelveHours, twentyFourHours, sevenDays, thirtyDays }
        var autoArchive: Threshold?
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/278"), arguments: [AutoArchiveThreshold.ninetyDays, .oneHundredEightyDays])
    func aLongThresholdSurvivesARelaunch(threshold: AutoArchiveThreshold) throws {
        var settings = AppSettings()
        settings.autoArchive = threshold
        let reloaded = try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(settings))
        #expect(reloaded.autoArchive == threshold)
        #expect(reloaded == settings)
    }

    /// 90 and 180 days are saved as 30 days, which every Cra reads, with the days beside them.
    /// An older Cra archives after 30 days instead of resetting every setting to 12 hours.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/278"))
    func aLongThresholdIsReadableByOlderCra() throws {
        var settings = AppSettings()
        settings.autoArchive = .oneHundredEightyDays
        let file = try Self.saved(settings)
        #expect(file["autoArchive"] as? String == "thirtyDays")
        #expect(file["autoArchiveDays"] as? Int == 180)
        let older = try ModelFixtureTests.decoder.decode(OlderCraSettings.self, from: ModelFixtureTests.encoder.encode(settings))
        #expect(older.autoArchive == .thirtyDays)

        settings.autoArchive = .sevenDays
        let short = try Self.saved(settings)
        #expect(short["autoArchive"] as? String == "sevenDays")
        #expect(short["autoArchiveDays"] == nil, "Arc's four thresholds save as before")
    }

    /// A value from a newer Cra loads as the longest threshold this one knows: archiving later than
    /// asked, never sooner. Until #278 it threw, settings.json went aside as corrupt and the
    /// defaults archived every Today tab unused for 12 hours.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/278"))
    func aValueFromANewerCraDoesNotResetTheFile() throws {
        let s = try Self.decode(#"{"autoArchive": "aValueFromTheFuture", "searchEngine": "ask", "autoArchiveEnabled": false, "newTabsAtTop": false}"#)
        #expect(s.autoArchive == .oneHundredEightyDays)
        #expect(s.searchEngine == .google)
        #expect(!s.autoArchiveEnabled && !s.newTabsAtTop, "the rest of the file loads as written")

        #expect(try Self.decode(#"{"autoArchive": "thirtyDays", "autoArchiveDays": 365}"#).autoArchive == .oneHundredEightyDays)
        #expect(try Self.decode(#"{"autoArchive": "thirtyDays", "autoArchiveDays": 60}"#).autoArchive == .ninetyDays,
                "days between two thresholds round up to the longer one")
        #expect(try Self.decode(#"{"autoArchive": "thirtyDays", "autoArchiveDays": "soon"}"#).autoArchive == .thirtyDays)
        #expect(try Self.decode("{}").autoArchive == .twelveHours, "no setting is still Arc's 12 hours")
    }

    /// What loaded from a newer Cra's value, or from days between thresholds, is saved so the next
    /// launch loads the same threshold (a test copy saved plain "thirtyDays" and came back at 30 days).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/278"), arguments: [
        #"{"autoArchive": "aValueFromTheFuture"}"#, #"{"autoArchive": "thirtyDays", "autoArchiveDays": 120}"#,
    ])
    func whatLoadedIsWhatIsSaved(json: String) throws {
        let loaded = try Self.decode(json)
        let file = try Self.saved(loaded)
        #expect(file["autoArchive"] as? String == "thirtyDays")
        #expect(file["autoArchiveDays"] as? Int == 180)
        #expect(try ModelFixtureTests.decoder.decode(AppSettings.self, from: ModelFixtureTests.encoder.encode(loaded)) == loaded)
    }
}
