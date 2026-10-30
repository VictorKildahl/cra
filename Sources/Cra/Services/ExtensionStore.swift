import AppKit
import CryptoKit
import Observation

/// Unpacked Chrome extensions, one folder each, loaded at start-up with
/// --load-extension by the Chrome-style page windows, plus the ones Chrome installed
/// into Cra's profile itself (Chrome Web Store, chrome://extensions "Load unpacked").
@MainActor
@Observable
final class ExtensionStore {
    struct Entry: Identifiable, Hashable {
        let id: String          // folder name
        let name: String
        let version: String
        let description: String
        let url: URL
        /// Chromium's extension ID (from the manifest key, else the folder path).
        var extensionID: String = ""
        /// Manifest icon for menus (16 px preferred).
        var icon: NSImage?
        /// action / browser_action / page_action default_popup, relative to the folder.
        var popupPath: String?
        /// options_ui.page or options_page, relative to the folder.
        var optionsPath: String?
        /// Installed by Chrome into the profile (Web Store); Chrome owns the folder and
        /// loads changes at once, so removing goes through chrome://extensions.
        var managedByChrome = false
        /// Chromium profile folders ("Default", "Profile <id>") it is installed in; nil for the
        /// --load-extension ones, which Chromium loads into every profile.
        var profiles: Set<String>?

        func isInstalled(inProfile name: String) -> Bool { profiles?.contains(name) ?? true }
    }

    /// The menu bar's Extensions menu and the toolbar read this one.
    static let shared = ExtensionStore()

    /// CraCEF loads the same folder (it also honours CRA_DATA_DIR).
    nonisolated static var directory: URL { AppPaths.supportDir.appendingPathComponent("Extensions", isDirectory: true) }

    nonisolated static func isInstalled(id: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(id).appendingPathComponent("manifest.json").path)
    }

    /// Copies an extension imported from Arc or Dia in as Extensions/<id>,
    /// replacing an older copy of the same extension.
    nonisolated static func importExtension(_ ext: ImportableExtension) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(ext.id, isDirectory: true)
        let staging = directory.appendingPathComponent(".\(ext.id).importing", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: ext.folder, to: staging)
        // Web Store verification hashes (_metadata) do not apply to an unpacked copy.
        try? fm.removeItem(at: staging.appendingPathComponent("_metadata"))
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: staging, to: dest)
    }

    private(set) var entries: [Entry] = []
    /// Set once the folder changed in this session; a restart loads the change.
    private(set) var needsRestart = false

    init() {
        reload()
        // Keep what was taken over from another browser, so it is only read once.
        if !FileManager.default.fileExists(atPath: Self.pinnedFile.path), !pinnedIDs.isEmpty { savePinned() }
    }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: ExtensionStore.directory, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: ExtensionStore.directory.path)) ?? []
        let list = names.sorted().compactMap { name in
            Self.entry(id: name, folder: ExtensionStore.directory.appendingPathComponent(name, isDirectory: true), extensionID: nil)
        }
        let loaded = Set(list.map(\.extensionID))
        // Each profile has its own Web Store extensions: note which profiles hold each one.
        let root = AppPaths.chromiumCache
        let profiles = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
        var managed: [Entry] = []
        for profile in profiles {
            for e in ExtensionImporter.extensions(inProfile: root.appendingPathComponent(profile, isDirectory: true))
            where e.isEnabled && !loaded.contains(e.id) {
                if let i = managed.firstIndex(where: { $0.extensionID == e.id }) { managed[i].profiles?.insert(profile); continue }
                guard var entry = Self.entry(id: e.id, folder: e.folder, extensionID: e.id) else { continue }
                entry.managedByChrome = true
                entry.profiles = [profile]
                managed.append(entry)
            }
        }
        entries = list + managed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        pinnedIDs.removeAll { id in !entries.contains { $0.extensionID == id } }
    }

    /// The extensions a page in this Chromium profile folder can run; running another
    /// profile's extension there crashes Chromium.
    func entries(inProfile name: String) -> [Entry] { entries.filter { $0.isInstalled(inProfile: name) } }

    private static func entry(id: String, folder dir: URL, extensionID: String?) -> Entry? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ k: String) -> String { (m[k] as? String) ?? "" }
        var title = ExtensionImporter.localized(str("name"), manifest: m, folder: dir)
        if title.hasPrefix("__MSG_") { title = id }
        let action = (m["action"] ?? m["browser_action"] ?? m["page_action"]) as? [String: Any]
        let options = (m["options_ui"] as? [String: Any])?["page"] as? String ?? m["options_page"] as? String
        return Entry(id: id, name: title.isEmpty ? id : title, version: str("version"), description: str("description"), url: dir,
                     extensionID: extensionID ?? chromiumID(key: m["key"] as? String, folder: dir),
                     icon: ExtensionImporter.icon(manifest: m, folder: dir, minPixels: 16),
                     popupPath: (action?["default_popup"] as? String).flatMap { $0.isEmpty ? nil : $0 }, optionsPath: options)
    }

    /// Chromium's ID: the first 128 bits of SHA-256 over the manifest key (or the
    /// unpacked folder's path), each hex digit mapped 0-f → a-p.
    static func chromiumID(key: String?, folder: URL) -> String {
        let input = key.flatMap { Data(base64Encoded: $0) } ?? Data(folder.path.utf8)
        let digest = SHA256.hash(data: input).prefix(16)
        let a = UInt8(ascii: "a")
        return String(decoding: digest.flatMap { [a + ($0 >> 4), a + ($0 & 0xF)] }, as: UTF8.self)
    }

    // MARK: Pinned extensions (Dia's Extensions ▸ Pin Extensions…; toolbar buttons)

    private static var pinnedFile: URL { AppPaths.file("pinned-extensions.json") }

    /// Chromium extension IDs in toolbar order.
    private(set) var pinnedIDs: [String] = ExtensionStore.loadPinned()

    /// Before Cra has a list of its own, the browser it replaces supplies one: Arc keeps its
    /// pinned extensions in Chromium's `extensions.pinned_extensions` pref, as do Dia and Chrome.
    private static func loadPinned() -> [String] {
        if let data = try? Data(contentsOf: pinnedFile) { return (try? JSONDecoder().decode([String].self, from: data)) ?? [] }
        for source in [ImportSource.arc, .dia] + ImportSource.allCases.filter({ $0.id == "chrome" }) {
            let prefs = source.dataDir.appendingPathComponent("Default/Preferences")
            guard let data = try? Data(contentsOf: prefs),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ids = (json["extensions"] as? [String: Any])?["pinned_extensions"] as? [String], !ids.isEmpty else { continue }
            return ids
        }
        return []
    }

    func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }

    func setPinned(_ id: String, _ pinned: Bool) {
        guard pinned != isPinned(id) else { return }
        if pinned { pinnedIDs.append(id) } else { pinnedIDs.removeAll { $0 == id } }
        savePinned()
    }

    func movePinned(_ id: String, to index: Int) {
        guard let from = pinnedIDs.firstIndex(of: id) else { return }
        pinnedIDs.remove(at: from)
        pinnedIDs.insert(id, at: min(max(0, index), pinnedIDs.count))
        savePinned()
    }

    private func savePinned() {
        try? JSONEncoder().encode(pinnedIDs).write(to: Self.pinnedFile, options: .atomic)
        NotificationCenter.default.post(name: .craPinnedExtensionsChanged, object: self)
    }

    // MARK: Toolbar icons (GitHub #9: a pinned extension's button in Cra's monochrome ink)

    /// How a pinned extension's button draws, keyed by Chromium extension ID, so it survives
    /// restarts and extension updates. The extension's own icon is untouched elsewhere.
    struct IconStyle: Codable, Equatable {
        /// Drawn as a template in the toolbar's ink instead of the extension's colours.
        var monochrome = false
        /// An SF Symbol in place of the extension's icon (always monochrome).
        var symbol: String?
        /// An image the user picked, copied into "Extension Icons".
        var imageFile: String?
    }

    /// Symbols offered in place of an extension's icon.
    static let iconSymbols = ["shield.lefthalf.filled", "lock.shield", "key", "lock", "person.badge.key",
                              "eye.slash", "hand.raised", "checkmark.shield", "bolt", "star", "bookmark",
                              "doc.text", "paintbrush", "globe", "puzzlepiece.extension"]

    private static var iconStylesFile: URL { AppPaths.file("extension-icons.json") }
    private static var customIconsDir: URL { AppPaths.supportDir.appendingPathComponent("Extension Icons", isDirectory: true) }

    private(set) var iconStyles: [String: IconStyle] = {
        guard let data = try? Data(contentsOf: ExtensionStore.iconStylesFile) else { return [:] }
        return (try? JSONDecoder().decode([String: IconStyle].self, from: data)) ?? [:]
    }()
    /// One image per extension, so the toolbar sees the same object until the style changes.
    @ObservationIgnored private var toolbarIcons: [String: NSImage] = [:]

    func iconStyle(_ id: String) -> IconStyle { iconStyles[id] ?? IconStyle() }

    func setIconStyle(_ id: String, _ style: IconStyle) {
        let old = iconStyle(id)
        guard style != old else { return }
        if let file = old.imageFile, file != style.imageFile {
            try? FileManager.default.removeItem(at: Self.customIconsDir.appendingPathComponent(file))
        }
        iconStyles[id] = style == IconStyle() ? nil : style
        toolbarIcons[id] = nil
        try? JSONEncoder().encode(iconStyles).write(to: Self.iconStylesFile, options: .atomic)
    }

    /// Copies `url` in as the extension's toolbar icon.
    func setCustomIcon(_ id: String, from url: URL) throws {
        guard NSImage(contentsOf: url) != nil else {
            throw NSError(domain: "Cra", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file is not an image."])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.customIconsDir, withIntermediateDirectories: true)
        // A new name each time: the old file is removed once the style no longer points at it.
        let name = "\(id)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        try fm.copyItem(at: url, to: Self.customIconsDir.appendingPathComponent(name))
        var style = iconStyle(id)
        style.symbol = nil
        style.imageFile = name
        setIconStyle(id, style)
    }

    /// The pinned button's image: the extension's icon, the user's replacement, or either as a
    /// template image (the button tints templates with the toolbar's ink).
    func toolbarIcon(for e: Entry) -> NSImage? {
        let style = iconStyle(e.extensionID)
        if style == IconStyle() { return e.icon }
        if let cached = toolbarIcons[e.extensionID] { return cached }
        var image: NSImage?
        if let symbol = style.symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: e.name)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            image?.isTemplate = true
        } else {
            if let file = style.imageFile {
                image = NSImage(contentsOf: Self.customIconsDir.appendingPathComponent(file)) ?? e.icon
            } else if style.monochrome {
                // From the largest icon: in the 16 px one a plate's edge and the mark blur together.
                let manifest = (try? Data(contentsOf: e.url.appendingPathComponent("manifest.json")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                image = manifest.flatMap { ExtensionImporter.icon(manifest: $0, folder: e.url, minPixels: 128) } ?? e.icon
            } else {
                image = e.icon
            }
            if style.monochrome { image = image.flatMap(Self.monochrome) }
        }
        toolbarIcons[e.extensionID] = image
        return image
    }

    /// An icon as a one-ink template, the way Arc's own toolbar glyphs read. An icon drawn on a
    /// plate (one colour covering most of it: Bitwarden's blue square, Vercel's black disc) keeps
    /// what stands out from the plate, so Bitwarden becomes its shield. Without a plate, colour
    /// reads as ink and white as none, so a white badge keeps only its mark. Ink is scaled so the
    /// strongest is solid; a one-colour glyph (nothing stands out) keeps its silhouette.
    static func monochrome(_ source: NSImage) -> NSImage? {
        let n = 64
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        source.draw(in: NSRect(x: 0, y: 0, width: n, height: n), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let count = n * n
        // Premultiplied: divide the alpha back out before judging the colour.
        func rgb(_ i: Int) -> (Double, Double, Double) {
            let a = Double(data[i * 4 + 3]) / 255
            return (Double(data[i * 4]) / 255 / a, Double(data[i * 4 + 1]) / 255 / a, Double(data[i * 4 + 2]) / 255 / a)
        }
        // The plate: the most common opaque colour (16 levels a channel), if it covers 40 % of the icon.
        var buckets: [Int: (n: Int, r: Double, g: Double, b: Double)] = [:]
        var visible = 0
        for i in 0..<count where data[i * 4 + 3] > 12 {
            visible += 1
            guard data[i * 4 + 3] > 240 else { continue }
            let (r, g, b) = rgb(i)
            let key = Int(r * 15.99) << 8 | Int(g * 15.99) << 4 | Int(b * 15.99)
            let o = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (o.n + 1, o.r + r, o.g + g, o.b + b)
        }
        let top = buckets.values.max { $0.n < $1.n }
        let plate = top.flatMap { t in Double(t.n) >= Double(visible) * 0.4 ? (t.r / Double(t.n), t.g / Double(t.n), t.b / Double(t.n)) : nil }
        var ink = [Double](repeating: 0, count: count)
        var inkMax = 0.0
        for i in 0..<count {
            let a = Double(data[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            let (r, g, b) = rgb(i)
            if let p = plate {
                ink[i] = a * min(1, ((r - p.0) * (r - p.0) + (g - p.1) * (g - p.1) + (b - p.2) * (b - p.2)).squareRoot() / 0.5)
            } else {
                ink[i] = a * max(0, 1 - (0.2126 * r + 0.7152 * g + 0.0722 * b))
            }
            inkMax = max(inkMax, ink[i])
        }
        let silhouette = inkMax < 0.08
        for i in 0..<count {
            let a = Double(data[i * 4 + 3]) / 255
            let v = silhouette ? a : min(max((ink[i] / inkMax - 0.1) / 0.5, 0), 1)
            let byte = UInt8((v * 255).rounded())
            data[i * 4] = 0; data[i * 4 + 1] = 0; data[i * 4 + 2] = 0; data[i * 4 + 3] = byte
        }
        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    /// Copies an unpacked extension folder (one that holds manifest.json) in.
    func add(folder: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) else {
            throw NSError(domain: "Cra", code: 1, userInfo: [NSLocalizedDescriptionKey: "That folder has no manifest.json."])
        }
        var dest = ExtensionStore.directory.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = ExtensionStore.directory.appendingPathComponent("\(folder.lastPathComponent)-\(n)", isDirectory: true)
            n += 1
        }
        try fm.copyItem(at: folder, to: dest)
        needsRestart = true
        reload()
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        needsRestart = true
        reload()
    }
}

extension Notification.Name {
    static let craPinnedExtensionsChanged = Notification.Name("craPinnedExtensionsChanged")
}
