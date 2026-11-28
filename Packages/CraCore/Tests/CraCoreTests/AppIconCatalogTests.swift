import Foundation
import Testing

/// macOS 26 draws an app's icon in the Dark, Clear and Tinted icon styles (System Settings ▸ Appearance ▸ Icon &
/// widget style) only from the bundle's own Icon Composer icon: an asset catalog (Assets.car) that names it in
/// CFBundleIconName. A legacy .icns stays as drawn in Dark, on Apple's grid or not: 0.1.58's sand Segments tile did
/// (GitHub #739). resources/AppIcon.icon (Gilad's, PR #690) is that icon, and scripts/compile-app-icon.sh compiles it
/// as scripts/build.sh does for Cra.app, with the .icns actool makes from it for macOS 14 and 15.
struct AppIconCatalogTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func theBundledIconHasALightADarkAndATintedLook() throws {
        let resources = Self.root.appendingPathComponent("resources")
        let alternates = try FileManager.default.contentsOfDirectory(at: resources.appendingPathComponent("app-icons"),
                                                                     includingPropertiesForKeys: nil)
        for document in [resources.appendingPathComponent("AppIcon.icon")] + alternates where document.pathExtension == "icon" {
            let name = document.deletingPathExtension().lastPathComponent
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("cra-app-icon-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            let compiled = try Self.run(Self.root.appendingPathComponent("scripts/compile-app-icon.sh").path, out.path, document.path)
            #expect(compiled.status == 0, "compile-app-icon.sh: \(compiled.output)")

            let plist = try #require(NSDictionary(contentsOf: out.appendingPathComponent("partial.plist")))
            #expect(plist["CFBundleIconName"] as? String == name)

            let info = try Self.run("/usr/bin/xcrun", "--sdk", "macosx", "assetutil", "--info", out.appendingPathComponent("Assets.car").path)
            let entries = try #require(try JSONSerialization.jsonObject(with: Data(info.output.utf8)) as? [[String: Any]])
            let looks = Set(entries.filter { $0["AssetType"] as? String == "IconImageStack" && $0["Name"] as? String == name }
                .compactMap { $0["Appearance"] as? String })
            #expect(looks.isSuperset(of: ["NSAppearanceNameAqua", "NSAppearanceNameDarkAqua", "ISAppearanceTintable"]), "\(name): \(looks)")
        }
    }

    /// Segments and Original use Xcode 27's glass materials in their four SVG layers.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/739")) func theIconKeepsGiladsMacOS27Features() throws {
        for path in ["resources/AppIcon.icon", "resources/app-icons/AppIcon-Original.icon"] {
            let json = try Data(contentsOf: Self.root.appendingPathComponent(path + "/icon.json"))
            let icon = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
            let features = try #require(icon["features"] as? [String])
            #expect(Set(features) == ["refractivity", "specular-location"])
            let groups = try #require(icon["groups"] as? [[String: Any]])
            #expect(groups.count == 4)
            #expect(groups.allSatisfy { $0["specular"] as? String == "inside" })
        }
    }

    private static func run(_ tool: String, _ arguments: String...) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
