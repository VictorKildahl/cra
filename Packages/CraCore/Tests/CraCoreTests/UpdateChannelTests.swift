import CraCore
import Foundation
import Testing

/// Stable and New update channels (GitHub #476): which feed each reads, and what Settings learns from it.
struct UpdateChannelTests {
    private let feed = "https://github.com/VictorKildahl/cra/releases/latest/download/appcast.xml"
    private let intel = "https://github.com/VictorKildahl/cra/releases/latest/download/appcast-intel.xml"

    @Test func newReadsTheBuildsOwnFeed() {
        #expect(UpdateChannel.new.feedURL(from: feed) == feed)
        #expect(UpdateChannel.new.feedURL(from: intel) == intel)
    }

    @Test func stableReadsTheStableFeedBesideIt() {
        #expect(UpdateChannel.stable.feedURL(from: feed)
            == "https://github.com/VictorKildahl/cra/releases/latest/download/appcast-stable.xml")
        #expect(UpdateChannel.stable.feedURL(from: intel)
            == "https://github.com/VictorKildahl/cra/releases/latest/download/appcast-stable-intel.xml")
        // A test's local feed (CRA_UPDATE_FEED) too.
        #expect(UpdateChannel.stable.feedURL(from: "http://127.0.0.1:8889/appcast.xml") == "http://127.0.0.1:8889/appcast-stable.xml")
    }

    /// A Mac that never chose starts on New: it runs a New build, and Sparkle would never take it back to Stable.
    @Test func aMacStartsOnNew() {
        #expect(UpdateChannel(stored: nil) == .new)
        #expect(UpdateChannel(stored: "beta") == .new)
        #expect(UpdateChannel(stored: "stable") == .stable)
    }

    /// The feed every Cra reads after `scripts/appcast.sh`: Stable, then the newest release, for engine builds only.
    @Test func readsBothReleasesOfTheMainFeed() {
        let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <title>Cra</title>
                <item>
                  <title>Cra 0.1.46</title>
                  <sparkle:version>202611171200</sparkle:version>
                  <sparkle:shortVersionString>0.1.46</sparkle:shortVersionString>
                  <sparkle:minimumUpdateVersion>202611161309</sparkle:minimumUpdateVersion>
                  <description><![CDATA[<h3>Notes</h3>]]></description>
                  <enclosure url="https://github.com/VictorKildahl/cra/releases/download/v0.1.46/Cra.zip" type="application/octet-stream" sparkle:edSignature="x" length="1"/>
                </item>
                <item>
                  <title>Cra 0.1.43</title>
                  <sparkle:version>202611131845</sparkle:version>
                  <sparkle:shortVersionString>0.1.43</sparkle:shortVersionString>
                  <enclosure url="https://github.com/VictorKildahl/cra/releases/download/v0.1.43/Cra-Intel.zip" type="application/octet-stream" sparkle:edSignature="y" length="2"/>
                </item>
              </channel>
            </rss>
            """
        let releases = AppcastRelease.parse(Data(xml.utf8))
        #expect(releases.map(\.version) == ["0.1.46", "0.1.43"])
        #expect(releases.map(\.build) == ["202611171200", "202611131845"])
        #expect(releases[1].diskImageURL == "https://github.com/VictorKildahl/cra/releases/download/v0.1.43/Cra-Intel.dmg")
    }

    @Test func aBrokenFeedHasNoReleases() {
        #expect(AppcastRelease.parse(Data("<html>Not Found".utf8)).isEmpty)
        #expect(AppcastRelease.parse(Data()).isEmpty)
    }

    /// Settings offers Stable's disk image only when Stable is older than the Mac's build.
    @Test func stableOlderThanTheMacIsADownload() {
        let stable = AppcastRelease(version: "0.1.43", build: "202611131845", archiveURL: "https://example.com/Cra.zip")
        #expect(stable.isOlder(than: "202611161908"))
        #expect(!stable.isOlder(than: "202611131845"))
        #expect(!stable.isOlder(than: "202611011200"))
        #expect(stable.isOlder(than: AppcastRelease.firstEngineBuild))
    }
}
