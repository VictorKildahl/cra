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
    /// Segments, then Arc's own icon set in Arc's order (its AppIcon cases: original, candy, hologram, neon,
    /// flutedGlass, schoolbook, colorful, and the canary and Early Birds channel icons), redrawn around Cra's C
    /// by Provok (github.com/mat-up/cra-icons, MIT; sources in brand/arc-icons), then Cra's earlier alternates.
    static let presets = [
        Option(id: defaultID, name: "Segments"),
        Option(id: "original", name: "Original"),
        Option(id: "candy", name: "Candy"),
        Option(id: "hologram", name: "Hologram"),
        Option(id: "neon", name: "Neon"),
        Option(id: "fluted-glass", name: "Fluted Glass"),
        Option(id: "schoolbook", name: "Schoolbook"),
        Option(id: "colorful", name: "Colorful"),
        Option(id: "canary", name: "Canary"),
        Option(id: "early-birds", name: "Early Birds"),
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

    /// The picked icon as the Dock tile gets it, Segments' too (AppIconBundle.dockImage). Chromium's
    /// download view draws it too (ChromiumDockTile).
    @ObservationIgnored private(set) var dockImage: NSImage?

    /// At start-up, before the Dock first draws the running app's tile. The bundle gets the picked icon
    /// again too: an update replaces Cra.app with one that has only its own (as Arc's applier does).
    func applyAtLaunch() {
        // Segments too: the Dock may still have the icon a pick put on the bundle last time (AppIconBundle.dockImage).
        setDockImage()
        applyToBundle(atLaunch: true)
    }

    /// Cra just came back to the Dock (Keep Cra in the menu bar, #231). macOS registers the app
    /// anew with the bundle's icon, so the ⌘-Tab switcher shows Segments until the icon is set
    /// again (GitHub #319).
    func applyAfterReturningToDock() {
        setDockImage()
        CraLog.note("app icon: \(selectedID) set again, back in the Dock")
    }

    func image(for id: String) -> NSImage? {
        // app-icons/segments.png is the bundled icon on the grid, for the picker; the Dock
        // gets AppIcon.icns itself (apply()).
        id == Self.customID ? customImage : imageURL(for: id).flatMap(NSImage.init(contentsOf:))
    }

    private func imageURL(for id: String) -> URL? {
        id == Self.customID ? Self.customURL : Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "app-icons")
    }

    /// `remember` false (cra://debug?appIcon=) shows the icon without writing the defaults, which a test
    /// copy shares with the installed Cra.
    func select(_ id: String, remember: Bool = true) {
        guard id == Self.defaultID || id == Self.customID || Self.presets.contains(where: { $0.id == id }) else { return }
        guard id != Self.customID || customImage != nil else { return }
        selectedID = id
        if remember { UserDefaults.standard.set(id, forKey: Keys.selected) }
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
        setDockImage()
        notifyDockTile()
        applyToBundle()
    }

    /// Cra.app's own changes, off the main thread and one after another (AppIconBundle).
    private static let bundleQueue = DispatchQueue(label: "dk.kildahl.cra.app-icon-bundle", qos: .utility)

    /// The picked icon on Cra.app, for Finder, /Applications, Launchpad and Spotlight, which never draw the
    /// Dock tile's (X, 20 Nov 2026); the bundle's own icon takes it off. Finder keeps it as a custom icon
    /// (an `Icon\r` file and a FinderInfo flag) outside Contents: `codesign --strict` names the attribute,
    /// but Gatekeeper accepts the app, as it does Arc.app carrying its picked icon the same way.
    private func applyToBundle(atLaunch: Bool = false) {
        let id = selectedID, defaultID = Self.defaultID
        let source = imageURL(for: id)
        let bundle = Bundle.main.bundleURL
        Self.bundleQueue.async {
            switch AppIconBundle.change(picked: id, defaultID: defaultID, bundleHasCustomIcon: Self.hasCustomIcon(bundle), atLaunch: atLaunch) {
            case .none:
                return
            case .put:
                guard let image = source.flatMap(NSImage.init(contentsOf:)) else {
                    CraLog.note("app icon: \(id) not put on the app, no image")
                    return
                }
                let done = NSWorkspace.shared.setIcon(image, forFile: bundle.path, options: [])
                CraLog.note("app icon: \(id) \(done ? "put on the app" : "not put on the app (can't write \(bundle.path))")")
            case .takeOff:
                let done = NSWorkspace.shared.setIcon(nil, forFile: bundle.path, options: [])
                CraLog.note("app icon: \(id) \(done ? "taken off the app" : "not taken off the app (can't write \(bundle.path))")")
            }
        }
    }

    /// For cra://debug?bundleIcon=<label>: Finder's custom icon flag on the app, and whether its `Icon\r`
    /// file holds an icon, read after the changes queued before it.
    func logBundleIcon(_ label: String) {
        let bundle = Bundle.main.bundleURL
        Self.bundleQueue.async {
            let fork = bundle.appendingPathComponent("Icon\r").path + "/..namedfork/rsrc"
            let size = ((try? FileManager.default.attributesOfItem(atPath: fork))?[.size] as? Int) ?? 0
            CraLog.note("bundle icon \(label): custom=\(Self.hasCustomIcon(bundle) ? 1 : 0) file=\(size > 0 ? 1 : 0)")
        }
    }

    nonisolated private static func hasCustomIcon(_ bundle: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        let n = getxattr(bundle.path, "com.apple.FinderInfo", &info, info.count, 0, 0)
        return n > 0 && AppIconBundle.hasCustomIcon(finderInfo: Array(info.prefix(n)))
    }

    private func setDockImage() {
        dockImage = AppIconBundle.dockImage(picked: selectedID, defaultID: Self.defaultID).flatMap(image(for:))
        // Setting applicationIconImage puts AppKit's image view on the tile in place of
        // Chromium's download view, whose badge would then be gone until Cra quits; it goes
        // back, drawing the new icon. nil puts the bundle's icon back.
        let chromiumView = NSApp.dockTile.contentView.flatMap { ChromiumDockTile.isChromiumView($0) ? $0 : nil }
        NSApp.applicationIconImage = dockImage
        if let chromiumView {
            NSApp.dockTile.contentView = chromiumView
            NSApp.dockTile.display()
        }
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

    /// What the Dock tile (and the ⌘-Tab switcher) gets while Cra runs, for
    /// cra://debug?dockTile (#319): "view=none" while the Dock draws the bundle's icon itself,
    /// else the tile's content view and whether its drawing is nearer the picked icon or the
    /// bundle's; then the downloads on Chromium's badge (#491).
    func dockTileReadout() -> String {
        guard let view = NSApp.dockTile.contentView else { return "view=none downloads=0 given=\(dockImage == nil ? "none" : selectedID)" }
        let px = 32
        let drawn = Self.pixels(px) { rect in
            guard view.bounds.width > 0, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: rect)
        }
        let bundleIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let picked = Self.pixels(px) { (self.image(for: self.selectedID) ?? bundleIcon).draw(in: $0) }
        let bundle = Self.pixels(px) { bundleIcon.draw(in: $0) }
        func distance(_ a: [UInt8], _ b: [UInt8]) -> Int {
            a.isEmpty || a.count != b.count ? Int.max : zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } / a.count
        }
        let toPicked = distance(drawn, picked), toBundle = distance(drawn, bundle)
        // downloads: the count on Chromium's badge, 0 while its view isn't on the tile. A Web Store
        // install's CRX download, which no list shows, must not be one (#491).
        let downloads = ChromiumDockTile.isChromiumView(view) ? (view.value(forKey: "downloads") as? Int ?? 0) : 0
        // given: the picture the app gave the Dock, none when it left the tile to the Dock's cache.
        return "view=\(type(of: view)) draws=\(toPicked < toBundle ? "picked" : "bundle") (\(toPicked) vs \(toBundle)) downloads=\(downloads) given=\(dockImage == nil ? "none" : selectedID)"
    }

    private static func pixels(_ px: Int, _ draw: (NSRect) -> Void) -> [UInt8] {
        guard let rep = bitmap(px), let ctx = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * px))
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
