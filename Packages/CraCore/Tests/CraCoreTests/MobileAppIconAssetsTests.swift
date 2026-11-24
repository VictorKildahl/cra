import CraCore
import Foundation
import Testing

struct MobileAppIconAssetsTests {
    /// Every icon the iPhone offers is in its asset catalog, as an icon set iOS can switch to and the picture the
    /// pickers show: 1024 px and without an alpha channel, which App Store Connect refuses. Without its set,
    /// `setAlternateIconName` fails and the home screen keeps the old icon (scripts/make-arc-icons.swift --ios and
    /// scripts/make-app-icons.swift --ios write them).
    @Test func everyIconHasItsSetAndPicture() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("iOS/Cra/Resources/Assets.xcassets")
        for icon in MobileAppIcon.allCases {
            let set = catalog.appendingPathComponent("\(icon.alternateName ?? "AppIcon").appiconset")
            let contents = try String(contentsOf: set.appendingPathComponent("Contents.json"), encoding: .utf8)
            #expect(contents.contains(#""filename" : "AppIcon.png""#) && contents.contains(#""size" : "1024x1024""#), "\(icon)")
            let png = try Data(contentsOf: set.appendingPathComponent("AppIcon.png"))
            #expect(Self.width(png) == 1024, "\(icon)'s icon is \(Self.width(png)) px")
            #expect(Self.colourType(png) == 2, "\(icon)'s icon has an alpha channel (PNG colour type \(Self.colourType(png)))")
            let preview = try Data(contentsOf: catalog.appendingPathComponent("\(icon.previewName).imageset/icon.png"))
            #expect(Self.width(preview) >= 512, "\(icon)'s picture is \(Self.width(preview)) px")
        }
    }

    /// The IHDR chunk's width and colour type (2 is RGB without alpha).
    private static func width(_ png: Data) -> Int { png.count > 24 ? Int(png[16]) << 24 | Int(png[17]) << 16 | Int(png[18]) << 8 | Int(png[19]) : 0 }
    private static func colourType(_ png: Data) -> Int { png.count > 25 ? Int(png[25]) : -1 }
}
