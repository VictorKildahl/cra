import AppKit

@main
struct AppIconResourcesTests {
    static func main() {
        guard let app = Bundle(path: CommandLine.arguments[1]) else { fatalError("Missing test app bundle") }
        precondition(AppIconResources.currentID(for: "midnight") == "segments")
        precondition(AppIconResources.currentID(for: "violet") == "colorful")
        for id in ["segments", "colorful", "mono", "custom"] {
            precondition(AppIconResources.currentID(for: id) == id)
        }
        let icons = ["segments", "original", "mono", "candy", "hologram", "neon", "fluted-glass", "schoolbook", "colorful", "canary", "early-birds"].map { id in
            guard let image = AppIconResources.image(named: id, in: app) else {
                fatalError("Could not load app icon \(id)")
            }
            if id != "segments" { checkIconBundle(id, app: app, image: image) }
            return pixels(image)
        }
        precondition(icons[0] != icons[1], "Each document should draw its own artwork")
        precondition(AppIconResources.image(named: "missing", in: app) == nil)
        if #available(macOS 26, *) {
            checkAppearanceRefresh()
            checkIconRendering()
        }
    }

    private static func checkIconBundle(_ id: String, app: Bundle, image: NSImage) {
        let label = id.split(separator: "-").map { $0.capitalized }.joined()
        let url = app.bundleURL.appendingPathComponent("Contents/Helpers/CraIcon-\(label.lowercased()).app")
        guard let bundle = Bundle(url: url), let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            fatalError("macOS badges \(id) as unavailable without a bundle executable")
        }
        let name = "AppIcon-\(label)"
        precondition(bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String == name)
        precondition(bundle.url(forResource: name, withExtension: "icns") != nil)
        let process = Process()
        process.executableURL = executable
        do { try process.run() } catch { fatalError("\(id) has an incompatible executable: \(error)") }
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        if #available(macOS 26, *) {
            precondition(image.representations.contains { $0.pixelsWide == 512 && $0.pixelsHigh == 512 },
                         "Dock magnification needs the full-size IconServices rendition")
            let reference = NSWorkspace.shared.icon(forFile: url.path)
            reference.size = NSSize(width: 512, height: 512)
            checkDetail(pixels(image, size: 512), against: pixels(reference, size: 512))
        }
    }

    // Check the full-size artwork after accounting for the measured change to its backing.
    private static func checkDetail(_ result: Data, against source: Data) {
        let center = (256 * 512 + 256) * 4
        let backing = (0..<3).map { Double(source[center + $0]) }
        let centerChange = (0..<4).map { Double(result[center + $0]) - Double(source[center + $0]) }
        var different = 0, samples = 0
        for pixel in stride(from: 0, to: source.count, by: 4 * 7) where source[pixel + 3] > 0 {
            let alpha = Double(source[pixel + 3]) / 255
            var contrast = 0.0
            for channel in 0..<3 {
                let difference = Double(source[pixel + channel]) - backing[channel] * alpha
                let range = difference < 0 ? backing[channel] : 255 - backing[channel]
                contrast = max(contrast, abs(difference) / max(1, range))
            }
            let backingCoverage = max(0, alpha - 2 * contrast)
            for channel in 0..<4 {
                let expected = Double(source[pixel + channel]) + centerChange[channel] * backingCoverage
                if abs(expected - Double(result[pixel + channel])) > 4 { different += 1 }
                samples += 1
            }
        }
        precondition(samples > 0 && different * 100 < samples, "The Dock image lost detail from the 512 px system icon")
    }

    private static func checkIconRendering() {
        func art(_ rgb: [Int]) -> NSImage {
            NSImage(size: NSSize(width: 32, height: 32), flipped: false) { bounds in
                NSColor(deviceRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255,
                        blue: CGFloat(rgb[2]) / 255, alpha: 1).setFill()
                bounds.insetBy(dx: 8, dy: 8).fill()
                NSColor.white.setFill()
                NSRect(x: 9, y: 9, width: 4, height: 4).fill()
                return true
            }
        }
        func render(_ style: String, rgb: [Int] = [153, 115, 77], systemDark: Bool = false, reduce: Bool = false) -> [UInt8] {
            Array(pixels(AppIconResources.renderedIcon(art(rgb), style: style,
                                                       reduceTransparency: reduce, systemDark: systemDark)))
        }
        let regular = render("RegularDark")
        let center = (64 * 128 + 64) * 4
        precondition(regular[center + 3] == 255)
        let highlight = stride(from: 0, to: regular.count, by: 4).first { regular[$0] == 255 && regular[$0 + 3] == 255 }!
        for style in ["ClearLight", "ClearDark", "TintedLight", "TintedDark"] {
            let dark = style.hasSuffix("Dark")
            let glass = render(style, systemDark: !dark)
            let backingAlpha = style.hasPrefix("Clear") ? 138...142 : (style == "TintedLight" ? 179...251 : 177...181)
            precondition(backingAlpha.contains(Int(glass[center + 3])), "\(style) should keep a visible, translucent backing")
            precondition(glass[3] == 0, "Clear corners should remain clear")
            precondition(glass[highlight] == 255 && glass[highlight + 3] == 255, "Keep the highlight legible")
            let automatic = style.hasPrefix("Clear") ? "ClearAutomatic" : "TintedAutomatic"
            precondition(render(automatic, systemDark: dark) == glass, "Automatic should follow the system appearance")
        }
        func checkBackdrop(_ style: String, native: [Int], dock: [Int], expected: [Int]) {
            let glass = render(style, rgb: native)
            let transmission = 1 - Double(glass[center + 3]) / 255
            for channel in 0..<3 {
                let shown = Double(glass[center + channel]) + transmission * Double(dock[channel])
                precondition(abs(shown - Double(expected[channel])) <= 2, "\(style) backing misses its Dock reference")
            }
        }
        // Native 512 px samples and Apple Dock references. The backdrop is inferred from the old rendered tile.
        checkBackdrop("ClearDark", native: [43, 43, 43], dock: [37, 37, 37], expected: [22, 22, 22])
        checkBackdrop("ClearLight", native: [125, 125, 125], dock: [38, 38, 38], expected: [93, 93, 93])
        checkBackdrop("TintedDark", native: [43, 31, 31], dock: [23, 33, 33], expected: [33, 25, 31])
        checkBackdrop("TintedLight", native: [255, 69, 83], dock: [0, 72, 50], expected: [125, 0, 0])
        checkBackdrop("TintedLight", native: [69, 83, 255], dock: [72, 50, 0], expected: [0, 0, 125])
        checkBackdrop("TintedDark", native: [31, 31, 43], dock: [33, 33, 23], expected: [25, 31, 33])
        checkBackdrop("TintedLight", native: [100, 100, 100], dock: [30, 30, 30], expected: [75, 75, 75])
        precondition(render("TintedLight", reduce: true) == regular)
        let translucent = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { bounds in
            NSColor(calibratedWhite: 0.5, alpha: 0.5).setFill()
            bounds.fill()
            return true
        }
        let original = AppIconResources.renderedIcon(translucent, style: nil, reduceTransparency: false)
        let clear = AppIconResources.renderedIcon(translucent, style: "ClearLight", reduceTransparency: false)
        precondition(pixels(clear) == pixels(original), "Preserve transparency provided by the system")
    }

    @MainActor
    private static func checkAppearanceRefresh() {
        var refreshed = false
        let observation = AppIconAppearanceObservation { refreshed = true }
        withExtendedLifetime(observation) {
            let defaults = UserDefaults.standard
            defaults.willChangeValue(forKey: "AppleIconAppearanceTheme")
            defaults.didChangeValue(forKey: "AppleIconAppearanceTheme")
            let deadline = Date(timeIntervalSinceNow: 1)
            while !refreshed && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            precondition(refreshed, "Changing the system icon style should refresh a selected preset")
        }
    }

    private static func pixels(_ image: NSImage, size: Int = 128) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.clear(bounds)
        image.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * size)
    }
}
