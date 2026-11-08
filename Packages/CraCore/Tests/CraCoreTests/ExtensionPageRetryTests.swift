import CraCore
import Foundation
import Testing

/// A restored extension page that Chromium blocked because the extension wasn't loaded yet.
struct ExtensionPageRetryTests {
    let options = "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html#general"
    let on: (String) -> Bool = { _ in true }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func retriesWithGrowingWaits() {
        let waits = (0..<ExtensionPageRetry.attempts).map { ExtensionPageRetry.delay(url: options, errorCode: -20, attempt: $0, isOn: on) }
        #expect(waits == [0.25, 0.5, 1, 2, 4, 4])
        #expect(ExtensionPageRetry.delay(url: options, errorCode: -20, attempt: ExtensionPageRetry.attempts, isOn: on) == nil)
    }

    /// Off or removed in the tab's profile: Chromium's error page stays.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func extensionThatIsOffIsNotRetried() {
        var asked: [String] = []
        let off: (String) -> Bool = { asked.append($0); return false }
        #expect(ExtensionPageRetry.delay(url: options, errorCode: -20, attempt: 0, isOn: off) == nil)
        #expect(asked == ["abcdefghijklmnopabcdefghijklmnop"])
    }

    @Test(arguments: [
        ("https://example.com/", -20),  // an ad blocker blocked a site
        ("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html", -105),  // another error
        ("chrome-extension:///options.html", -20),
        ("chrome://extensions", -20),
    ])
    func otherFailuresAreLeft(url: String, code: Int) {
        #expect(ExtensionPageRetry.delay(url: url, errorCode: code, attempt: 0, isOn: on) == nil)
    }

    @Test func extensionIDs() {
        #expect(ExtensionPageRetry.extensionID(of: options) == "abcdefghijklmnopabcdefghijklmnop")
        #expect(ExtensionPageRetry.extensionID(of: "https://example.com/") == nil)
    }
}
