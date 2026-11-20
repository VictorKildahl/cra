import CraCore
import Testing

struct ArchiveLimitTests {
    /// GitHub #614: the archive dropped everything past 2,000 closed tabs, so a Clear Today of 5,000 lost
    /// 3,000. It keeps 10,000 now.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/614"))
    func theArchiveKeepsTenThousandTabs() {
        #expect(ArchiveLimit.kept == 10_000)
        #expect(ArchiveLimit.overflow(5_000) == 0)
        #expect(ArchiveLimit.overflow(10_000) == 0)
        #expect(ArchiveLimit.overflow(10_003) == 3)
    }
}
