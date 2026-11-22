import AppKit
import simd

public enum AppIconResources {
    /// Finder and other clients that request the installed app's file icon.
    public static func setFileIcon(_ image: NSImage?, on app: Bundle) -> Bool {
        guard canUpdateFileIcon(at: app.bundleURL) else { return false }
        return NSWorkspace.shared.setIcon(image, forFile: app.bundlePath, options: [])
    }

    public static func canUpdateFileIcon(at url: URL) -> Bool {
        // Writing Finder metadata on a development build inside Documents can trigger a folder-access prompt.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return url.pathExtension == "app" && !documents.contains { url.pathComponents.starts(with: $0.pathComponents) }
    }

    public static func image(named id: String, in app: Bundle) -> NSImage? {
        guard !id.contains("/") else { return nil }
        if let png = app.url(forResource: id, withExtension: "png", subdirectory: "app-icons") {
            return NSImage(contentsOf: png)
        }
        let url = app.bundleURL.appendingPathComponent("Contents/Helpers/CraIcon-\(id).app")
        guard let helper = Bundle(url: url), let executable = helper.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path),
              let name = helper.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
              let artwork = helper.url(forResource: name, withExtension: "icns") else { return nil }
        if #available(macOS 26, *) {
            let workspace = NSWorkspace.shared
            return renderedIcon(workspace.icon(forFile: helper.bundlePath),
                                style: UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme"),
                                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
        }
        return NSImage(contentsOf: artwork)
    }

    static func renderedIcon(_ icon: NSImage, style: String?, reduceTransparency: Bool,
                             systemDark: Bool = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark") -> NSImage {
        // IconServices starts at 32 pt. Request its 512 px rendition before AppKit snapshots the tile.
        let side = 512
        icon.size = NSSize(width: side, height: side)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return icon }
        let bounds = NSRect(origin: .zero, size: icon.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(bounds)
        icon.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        if !reduceTransparency, let style {
            let tinted = style.hasPrefix("Tinted")
            let dark = style.hasSuffix("Dark") || (!style.hasSuffix("Light") && systemDark)
            if tinted || style.hasPrefix("Clear") { adjustBacking(in: bitmap, tinted: tinted, dark: dark) }
        }
        let result = NSImage(size: bounds.size)
        result.addRepresentation(bitmap)
        return result
    }

    private static func dockBacking(_ rgb: SIMD3<Float>, tinted: Bool, dark: Bool) -> (premultiplied: SIMD3<Float>, opacity: Float) {
        if !tinted {
            // At fixed opacity, a change in premultiplied RGB adds the same change over any Dock backdrop.
            let color = dark ? rgb * (0.55 * 0.78) - 13 : rgb * 0.55 + 7
            return (color, 0.55)
        }

        let chroma = rgb - rgb.min()
        if dark {
            // The red Dock reference needs (+3, -2, +4). Rotate that correction with the native hue.
            let hue = chroma / max(12, chroma.sum())
            let shift = SIMD3<Float>(3, -2, 4) * hue.x + SIMD3<Float>(4, 3, -2) * hue.y + SIMD3<Float>(-2, 4, 3) * hue.z
            return (rgb * (0.70 * 0.78) + shift, 0.70)
        }

        // In Light, saturated tints need a deep colored backing. Let pale and gray tints keep their transparency.
        let span = chroma.max()
        let strength = min(1, span / max(1, rgb.max() * 0.55))
        let hue = simd_max(chroma - span * 0.08, .zero) / max(1, span * 0.92)
        let original = rgb * 0.94
        let saturated = hue * (rgb.max() * 0.50)
        let opacity = 0.70 + 0.28 * strength
        return ((original + (saturated - original) * strength) * opacity, opacity)
    }

    // IconServices bakes the Clear/Tinted backing into the image it gives a custom Dock tile.
    // Both C-shaped presets expose that backing at the center, so we can adjust its color and
    // opacity independently while preserving the foreground and its highlights.
    private static func adjustBacking(in bitmap: NSBitmapImageRep, tinted: Bool, dark: Bool) {
        guard let data = bitmap.bitmapData else { return }
        let center = data + (bitmap.pixelsHigh / 2) * bitmap.bytesPerRow + (bitmap.pixelsWide / 2) * 4
        guard center[3] == 255 else { return }
        let backing = SIMD3(Float(center[0]), Float(center[1]), Float(center[2]))
        let target = dockBacking(backing, tinted: tinted, dark: dark)
        let one = SIMD3<Float>(repeating: 1)
        let lighter = one / simd_max(255 - backing, one)
        let darker = one / simd_max(backing, one)
        let colorChange = simd_clamp(target.premultiplied, .zero, one * (255 * target.opacity)) - backing
        for y in 0..<bitmap.pixelsHigh {
            var pixel = data + y * bitmap.bytesPerRow
            for _ in 0..<bitmap.pixelsWide {
                let alpha = Float(pixel[3]) / 255
                let rgb = SIMD3(Float(pixel[0]), Float(pixel[1]), Float(pixel[2]))
                let difference = rgb - backing * alpha
                let contrast = max((difference * lighter).max(), (-difference * darker).max())
                // Keep strokes and specular highlights solid as their contrast increases.
                let backingAlpha = max(0, alpha - 2 * contrast)
                let removed = backingAlpha * (1 - target.opacity)
                let color = rgb + colorChange * backingAlpha
                pixel[0] = UInt8(clamping: Int(color.x.rounded()))
                pixel[1] = UInt8(clamping: Int(color.y.rounded()))
                pixel[2] = UInt8(clamping: Int(color.z.rounded()))
                pixel[3] = UInt8(clamping: Int(((alpha - removed) * 255).rounded()))
                pixel += 4
            }
        }
    }
}

/// Icon style, automatic light/dark switching, and the accent used for tinted icons
/// can all change in System Settings while Cra or the Dock plug-in is running.
public final class AppIconAppearanceObservation: NSObject {
    private let keys = ["AppleIconAppearanceTheme", "AppleInterfaceStyle", "AppleAccentColor"]
    private let changed: @MainActor () -> Void

    public init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        super.init()
        for key in keys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceAppearanceDidChange(_:)),
            name: Notification.Name("NSWorkspaceIconAppearanceConfigurationDidChangeNotification"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceAppearanceDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                      change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        scheduleRefresh()
    }

    @objc private func workspaceAppearanceDidChange(_ notification: Notification) {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.async { [weak self] in self?.changed() }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for key in keys { UserDefaults.standard.removeObserver(self, forKeyPath: key) }
    }
}
