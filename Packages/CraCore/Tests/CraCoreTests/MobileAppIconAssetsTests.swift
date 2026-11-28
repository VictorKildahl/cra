import CraCore
import Foundation
import Testing

struct MobileAppIconAssetsTests {
    @Test func everyIconUsesItsSharedIconComposerDocument() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = root.appendingPathComponent("iOS/Cra/Resources/Assets.xcassets")
        for icon in MobileAppIcon.allCases {
            let name = icon.alternateName ?? "AppIcon"
            let directory = icon == .segments ? "resources" : "resources/app-icons"
            let document = root.appendingPathComponent("\(directory)/\(name).icon/icon.json")
            #expect(FileManager.default.fileExists(atPath: document.path))
            #expect(!FileManager.default.fileExists(atPath: catalog.appendingPathComponent("\(name).appiconset").path))
            #expect(!FileManager.default.fileExists(atPath: catalog.appendingPathComponent("\(icon.previewName).imageset").path))
        }
    }
}
