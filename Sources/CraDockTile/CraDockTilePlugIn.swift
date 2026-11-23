import AppKit

/// Cra's Dock tile plug-in (NSDockTilePlugIn in Info.plist): the Dock loads it while Cra
/// is in the Dock but not running, so the icon picked in Settings stays after Cra quits.
/// Arc and Dia ship the same kind of plug-in. It runs in the Dock's plug-in host, reads
/// the choice from Cra's defaults and the images from Cra's bundle or data folder, and
/// redraws when Cra posts "<bundle id>.appIconChanged" (AppIconManager).
@objc(CraDockTilePlugIn)
final class CraDockTilePlugIn: NSObject, NSDockTilePlugIn {
    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?
    /// Cra.app, three levels up from Contents/PlugIns/CraDockTile.docktileplugin.
    private let app: Bundle? = Bundle(url: Bundle(for: CraDockTilePlugIn.self).bundleURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())

    func setDockTile(_ dockTile: NSDockTile?) {
        tile = dockTile
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        guard dockTile != nil, let id = app?.bundleIdentifier else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(id + ".appIconChanged"), object: nil, queue: .main) { [weak self] _ in self?.update() }
        update()
    }

    private func update() {
        guard let tile else { return }
        if let image = selectedImage() {
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            tile.contentView = view
        } else {
            // No content view: the Dock draws the bundle's own icon.
            tile.contentView = nil
        }
        tile.display()
    }

    /// The keys AppIconManager writes. Segments, the bundle's own, is drawn too: left to the Dock, the bundle's icon
    /// came from the Dock's cache, which can still be the icon a pick put on Cra.app before (AppIconBundle.dockImage).
    private func selectedImage() -> NSImage? {
        guard let app, let id = app.bundleIdentifier as CFString? else { return nil }
        CFPreferencesAppSynchronize(id)
        let selected = CFPreferencesCopyAppValue("appIcon" as CFString, id) as? String ?? "segments"
        if selected == "custom" {
            return (CFPreferencesCopyAppValue("appIconCustomPath" as CFString, id) as? String).flatMap(NSImage.init(contentsOfFile:))
        }
        return app.url(forResource: selected, withExtension: "png", subdirectory: "app-icons").flatMap(NSImage.init(contentsOf:))
    }
}
