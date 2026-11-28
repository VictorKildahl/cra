import CraCore
import Foundation
import Testing

struct MobileAppIconAssetsTests {
    /// Each iOS icon has a picker image and either an Icon Composer document or a 1024 px opaque icon set.
    @Test func everyIconHasItsSetAndPicture() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = root.appendingPathComponent("iOS/Cra/Resources/Assets.xcassets")
        for icon in MobileAppIcon.allCases {
            let name = icon.alternateName ?? "AppIcon"
            let set = catalog.appendingPathComponent("\(name).appiconset")
            if [.segments, .original, .candy, .hologram, .neon, .flutedGlass, .schoolbook, .colorful].contains(icon) {
                let directory = icon == .segments ? "resources" : "resources/app-icons"
                let document = root.appendingPathComponent("\(directory)/\(name).icon/icon.json")
                #expect(FileManager.default.fileExists(atPath: document.path))
                #expect(!FileManager.default.fileExists(atPath: set.path))
                continue
            }
            let preview = try Data(contentsOf: catalog.appendingPathComponent("\(icon.previewName).imageset/icon.png"))
            #expect(Self.width(preview) >= 512, "\(icon)'s picture is \(Self.width(preview)) px")
            let contents = try String(contentsOf: set.appendingPathComponent("Contents.json"), encoding: .utf8)
            #expect(contents.contains(#""filename" : "AppIcon.png""#) && contents.contains(#""size" : "1024x1024""#), "\(icon)")
            let png = try Data(contentsOf: set.appendingPathComponent("AppIcon.png"))
            #expect(Self.width(png) == 1024, "\(icon)'s icon is \(Self.width(png)) px")
            #expect(Self.colourType(png) == 2, "\(icon)'s icon has an alpha channel (PNG colour type \(Self.colourType(png)))")
        }
    }

    /// The IHDR chunk's width and colour type (2 is RGB without alpha).
    private static func width(_ png: Data) -> Int { png.count > 24 ? Int(png[16]) << 24 | Int(png[17]) << 16 | Int(png[18]) << 8 | Int(png[19]) : 0 }
    private static func colourType(_ png: Data) -> Int { png.count > 25 ? Int(png[25]) : -1 }
}
