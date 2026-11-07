import CraCore
import Foundation
import Testing

/// Arc's "Archive Little Arcs after:" (Settings ▸ Links, Arc 1.172.1): 1 hour, 6 hours (default), 12 hours.
struct LittleWindowArchiveTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func archivesOnceTheTimeIsUp() {
        let a = LittleWindowArchive.sixHours
        #expect(!a.expired(lastUsed: start, now: start.addingTimeInterval(6 * 3600 - 1), isKey: false))
        #expect(a.expired(lastUsed: start, now: start.addingTimeInterval(6 * 3600), isKey: false))
    }

    @Test func neverTheOneInUse() {
        #expect(!LittleWindowArchive.oneHour.expired(lastUsed: start, now: start.addingTimeInterval(86400), isKey: true))
    }

    @Test func arcsChoicesAndDefault() throws {
        #expect(LittleWindowArchive.allCases.map(\.label) == ["1 hour", "6 hours (default)", "12 hours"])
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).littleWindowArchiveAfter == .sixHours)
    }
}
