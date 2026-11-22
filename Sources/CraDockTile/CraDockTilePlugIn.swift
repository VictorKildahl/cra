import AppKit
import CraAppIcons

/// Cra's Dock tile plug-in (NSDockTilePlugIn in Info.plist): the Dock loads it while Cra
/// is in the Dock but not running, so the icon picked in Settings stays after Cra quits.
/// Arc and Dia ship the same kind of plug-in. It runs in the Dock's plug-in host, reads
/// the choice from Cra's defaults and the images from Cra's bundle or data folder, and
/// redraws when Cra posts "<bundle id>.appIconChanged" (AppIconManager).
@objc(CraDockTilePlugIn)
final class CraDockTilePlugIn: NSObject, NSDockTilePlugIn {
    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?
    private var appearanceObservation: AppIconAppearanceObservation?
    /// Cra.app, three levels up from Contents/PlugIns/CraDockTile.docktileplugin.
    private let app: Bundle? = Bundle(url: Bundle(for: CraDockTilePlugIn.self).bundleURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())

    func setDockTile(_ dockTile: NSDockTile?) {
        tile = dockTile
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        appearanceObservation = nil
        guard dockTile != nil, let id = app?.bundleIdentifier else { return }
        if #available(macOS 26, *) {
            appearanceObservation = AppIconAppearanceObservation { [weak self] in self?.update() }
        }
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

    /// An explicit Segments selection draws its bundled image here, just as in the running app.
    private func selectedImage() -> NSImage? {
        guard let app, let id = app.bundleIdentifier as CFString? else { return nil }
        CFPreferencesAppSynchronize(id)
        guard let selected = CFPreferencesCopyAppValue("appIcon" as CFString, id) as? String else { return nil }
        if selected == "custom" {
            return (CFPreferencesCopyAppValue("appIconCustomPath" as CFString, id) as? String).flatMap(NSImage.init(contentsOfFile:))
        }
        return AppIconResources.image(named: selected, in: app)
    }
}
