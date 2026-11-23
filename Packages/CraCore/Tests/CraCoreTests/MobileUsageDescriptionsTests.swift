import CraCore
import Foundation
import Testing

struct MobileUsageDescriptionsTests {
    /// Every usage description something in the iPhone app (or WebKit, for a page) can ask for is in its Info.plist:
    /// without NSPhotoLibraryAddUsageDescription, Save to Photos on a long-pressed image ended the app (#713).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/713"))
    func theInfoPlistDescribesEverythingAPageCanAskFor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("iOS/Support/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for (key, why) in MobileUsageDescriptions.required {
            let text = (plist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            #expect(!text.isEmpty, "Info.plist needs \(key), for \(why)")
        }
    }
}
