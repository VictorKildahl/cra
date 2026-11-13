import CraCore
import Foundation
import Testing

/// Running a staged update once before it is installed, so its first launch skips macOS's check.
struct UpdatePrewarmTests {
    let id = "dk.kildahl.cra"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func copy(_ path: String, _ version: String?, id: String? = "dk.kildahl.cra", at offset: TimeInterval = 0) -> UpdatePrewarm.Candidate {
        .init(path: path, version: version, bundleID: id, modified: t0.addingTimeInterval(offset))
    }

    @Test func picksTheStagedCopyOfThisUpdate() {
        let picked = UpdatePrewarm.pick([copy("/a/Cra.app", "0.1.40"), copy("/b/Cra.app", "0.1.42")], version: "0.1.42", bundleID: id)
        #expect(picked?.path == "/b/Cra.app")
    }

    @Test func newestWhenSparkleLeftSeveral() {
        let picked = UpdatePrewarm.pick([copy("/old/Cra.app", "0.1.42", at: 0), copy("/new/Cra.app", "0.1.42", at: 60)],
                                        version: "0.1.42", bundleID: id)
        #expect(picked?.path == "/new/Cra.app")
    }

    @Test func neverAnotherAppOrAnUnreadableCopy() {
        // Another app's bundle in the folder, or one whose Info.plist couldn't be read, never runs.
        #expect(UpdatePrewarm.pick([copy("/x/Other.app", "0.1.42", id: "com.example.other"), copy("/y/Cra.app", nil)],
                                   version: "0.1.42", bundleID: id) == nil)
        #expect(UpdatePrewarm.pick([], version: "0.1.42", bundleID: id) == nil)
    }

    @Test func helpersRunToo() {
        // Each helper app is its own program, checked on its first start; frameworks are not run.
        let entries = ["Chromium Embedded Framework.framework", "Cra Helper (GPU).app", "Cra Helper.app",
                       "Sparkle.framework", "Cra Helper (Renderer).app"]
        #expect(UpdatePrewarm.helperExecutables(frameworkEntries: entries) == [
            "Contents/Frameworks/Cra Helper (GPU).app/Contents/MacOS/Cra Helper (GPU)",
            "Contents/Frameworks/Cra Helper (Renderer).app/Contents/MacOS/Cra Helper (Renderer)",
            "Contents/Frameworks/Cra Helper.app/Contents/MacOS/Cra Helper",
        ])
    }

    @Test func runsAtOnceThenEveryTwentyMinutes() {
        #expect(UpdatePrewarm.isDue(lastRun: nil, now: t0))
        #expect(!UpdatePrewarm.isDue(lastRun: t0, now: t0.addingTimeInterval(19 * 60)))
        #expect(UpdatePrewarm.isDue(lastRun: t0, now: t0.addingTimeInterval(20 * 60)))
    }
}
