import AppKit
import Observation
import UniformTypeIdentifiers

/// The app icon picked in Settings ▸ General: the bundled Segments icon, one of the
/// alternates in resources/app-icons, or an image of the user's own. Arc does the same
/// (AppIconClient + a Dock tile plug-in): the running app swaps
/// `NSApp.applicationIconImage`, and CraDockTile keeps the choice in the Dock after Cra
/// quits. The plug-in runs in the Dock's process, so the choice lives in Cra's defaults
/// (which it reads) rather than settings.json under the data folder (which it can't find).
@MainActor
@Observable
final class AppIconManager {
    static let shared = AppIconManager()

    struct Option: Identifiable, Equatable {
        let id: String
        let name: String
    }

    static let defaultID = "segments"
    static let customID = "custom"
    static let presets = [
        Option(id: defaultID, name: "Segments"),
        Option(id: "midnight", name: "Midnight"),
        Option(id: "mono", name: "Mono"),
        Option(id: "violet", name: "Violet"),
    ]

    // Shared with Sources/CraDockTile.
    private enum Keys {
        static let selected = "appIcon"
        static let customPath = "appIconCustomPath"
    }
    private static var changedNotification: Notification.Name {
        Notification.Name((Bundle.main.bundleIdentifier ?? "dk.kildahl.cra") + ".appIconChanged")
    }

    private(set) var selectedID: String
    /// The user's own icon, kept even while a preset is selected.
    private(set) var customImage: NSImage?

    private static var customURL: URL { AppPaths.file("AppIcon.png") }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Keys.selected) ?? Self.defaultID
        let custom = NSImage(contentsOf: Self.customURL)
        let known = Self.presets.contains { $0.id == stored } || (stored == Self.customID && custom != nil)
        selectedID = known ? stored : Self.defaultID
        customImage = custom
    }

    /// At start-up, before the Dock first draws the running app's tile.
    func applyAtLaunch() {
        if selectedID != Self.defaultID { NSApp.applicationIconImage = image(for: selectedID) }
    }

    func image(for id: String) -> NSImage? {
        // app-icons/segments.png is the bundled icon on the grid, for the picker; the Dock
        // gets AppIcon.icns itself (apply()).
        id == Self.customID ? customImage
            : Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "app-icons").flatMap(NSImage.init(contentsOf:))
    }

    func select(_ id: String) {
        guard id != Self.customID || customImage != nil else { return }
        selectedID = id
        UserDefaults.standard.set(id, forKey: Keys.selected)
        apply()
    }

    /// Makes an icon of any image file and selects it. Throws when it isn't an image.
    func setCustom(from url: URL) throws {
        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0,
              let png = Self.iconPNG(from: source) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        try png.write(to: Self.customURL, options: .atomic)
        customImage = NSImage(data: png)
        UserDefaults.standard.set(Self.customURL.path, forKey: Keys.customPath)
        select(Self.customID)
    }

    func removeCustom() {
        try? FileManager.default.removeItem(at: Self.customURL)
        customImage = nil
        UserDefaults.standard.removeObject(forKey: Keys.customPath)
        if selectedID == Self.customID { select(Self.defaultID) } else { notifyDockTile() }
    }

    private func apply() {
        // nil puts the bundle's icon back.
        NSApp.applicationIconImage = selectedID == Self.defaultID ? nil : image(for: selectedID)
        notifyDockTile()
    }

    private func notifyDockTile() {
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Apple's macOS icon grid: the tile is 824 of 1024 px, centred. The Dock fits the bundled
    /// AppIcon.icns (drawn edge to edge) into it by itself, but draws applicationIconImage and
    /// the plug-in's image as they are, so every alternate and custom icon is made on the grid.
    static let gridBody: CGFloat = 824.0 / 1024

    /// 512 px on Apple's grid, like the alternates. An opaque image (a photo, a logo on a
    /// background) fills Cra's rounded tile. One with transparent corners (a finished app
    /// icon, a cut-out logo) is scaled so its visible part fits the tile's square, bigger or
    /// smaller than it came. Either way nothing reaches past where other Dock icons end.
    static func iconPNG(from source: NSImage) -> Data? {
        let px = 512
        guard let rep = bitmap(px), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let canvas = NSRect(x: 0, y: 0, width: px, height: px)
        let body = canvas.insetBy(dx: CGFloat(px) * (1 - gridBody) / 2, dy: CGFloat(px) * (1 - gridBody) / 2)
        let shape = analyse(source)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        if let visible = shape.visible, shape.cutOut {
            let size = source.size
            let content = NSSize(width: visible.width * size.width, height: visible.height * size.height)
            let target = fit(content, in: body, fill: false)
            let scale = target.width / content.width
            source.draw(in: NSRect(x: target.minX - visible.minX * size.width * scale, y: target.minY - visible.minY * size.height * scale,
                                   width: size.width * scale, height: size.height * scale))
        } else {
            // AppIcon.icns's tile: 14.3-unit corners on 64.
            let radius = body.width * 14.3 / 64
            NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).addClip()
            source.draw(in: fit(source.size, in: body, fill: true))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Whether the image's corners are transparent, and its more-than-half-opaque part as
    /// fractions of its size (origin bottom left), nil when nothing is.
    private static func analyse(_ image: NSImage) -> (cutOut: Bool, visible: NSRect?) {
        let px = 256
        guard let rep = bitmap(px), let ctx = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return (false, nil) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))  // stretched: only fractions are read
        NSGraphicsContext.restoreGraphicsState()
        // RGBA rows from the top.
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * rep.bytesPerRow + x * 4 + 3] }
        let cutOut = [(1, 1), (px - 2, 1), (1, px - 2), (px - 2, px - 2)].allSatisfy { alpha($0.0, $0.1) < 26 }
        var minX = px, minY = px, maxX = -1, maxY = -1
        for y in 0..<px {
            for x in 0..<px where alpha(x, y) > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return (cutOut, nil) }
        let n = CGFloat(px)
        return (cutOut, NSRect(x: CGFloat(minX) / n, y: CGFloat(px - 1 - maxY) / n,
                               width: CGFloat(maxX - minX + 1) / n, height: CGFloat(maxY - minY + 1) / n))
    }

    private static func bitmap(_ px: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    private static func fit(_ size: NSSize, in rect: NSRect, fill: Bool) -> NSRect {
        let scale = fill ? max(rect.width / size.width, rect.height / size.height) : min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
