import CraCore
import Foundation
import Testing

/// Cra.app replaced on disk while it runs (`brew upgrade --greedy`): the restart Cra offers for it.
struct InstalledBundleTests {
    private let running = InstalledBundle.Version(short: "0.1.54", build: "202611201200")

    @Test func aNewerBundleOnDiskIsOneRestartAway() {
        let newer = InstalledBundle.Version(short: "0.1.55", build: "202611231500")
        #expect(InstalledBundle.replacement(running: running, onDisk: newer) == "0.1.55")
    }

    /// A rebuild of the same version (a dev build, a re-signed release) is another build all the same.
    @Test func anotherBuildOfTheSameVersionCounts() {
        let rebuilt = InstalledBundle.Version(short: "0.1.54", build: "202611231500")
        #expect(InstalledBundle.replacement(running: running, onDisk: rebuilt) == "0.1.54")
    }

    @Test func theRunningBundleOrNoneAsksNothing() {
        #expect(InstalledBundle.replacement(running: running, onDisk: running) == nil)
        #expect(InstalledBundle.replacement(running: running, onDisk: nil) == nil)
    }

    @Test func readsAnInfoPlist() throws {
        let plist: [String: Any] = ["CFBundleShortVersionString": "0.1.55", "CFBundleVersion": "202611231500",
                                    "CFBundleExecutable": "Cra"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(InstalledBundle.Version(infoPlist: data) == .init(short: "0.1.55", build: "202611231500"))
    }

    /// A bundle half copied in or a broken file is no version, so no restart into it.
    @Test func aPartialOrBrokenPlistIsNoVersion() throws {
        let partial = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "0.1.55"],
                                                         format: .xml, options: 0)
        #expect(InstalledBundle.Version(infoPlist: partial) == nil)
        #expect(InstalledBundle.Version(infoPlist: Data("not a plist".utf8)) == nil)
        #expect(InstalledBundle.Version(infoPlist: Data()) == nil)
    }
}
