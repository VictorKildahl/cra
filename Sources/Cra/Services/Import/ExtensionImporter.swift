import AppKit
import Foundation

/// A Chrome extension installed in Arc or Dia, read from the profile's
/// `Secure Preferences` (extensions.settings). Web Store installs keep their
/// manifest `key`, so a copy loaded unpacked keeps the same extension ID.
struct ImportableExtension: Identifiable {
    let id: String
    let name: String
    let version: String
    let folder: URL
    /// Turned on in at least one of `profiles`.
    var isEnabled: Bool
    let icon: NSImage?
    /// The source profile folders it is installed in, and whether it is on there (GitHub #131).
    var profiles: [String: Bool] = [:]

    /// Where Cra loads it: the profiles that have it on, else (picked though off) every one that has it.
    var sourceProfiles: Set<String> {
        let on = Set(profiles.filter(\.value).keys)
        return on.isEmpty ? Set(profiles.keys) : on
    }
}

enum ExtensionImporter {
    /// Chrome's Manifest::Location: 1 internal (Web Store), 4 unpacked. Component
    /// (5) and external installs belong to the browser itself and are skipped.
    private static let importableLocations: Set<Int> = [1, 4]

    static func extensions(inBrowserSupportDir supportDir: URL) -> [ImportableExtension] {
        extensions(inUserData: supportDir.appendingPathComponent("User Data", isDirectory: true))
    }

    /// Every profile under a Chromium "User Data" folder (Chrome, Brave, Edge… keep it at the top level),
    /// one entry per extension with the profiles that have it.
    static func extensions(inUserData userData: URL) -> [ImportableExtension] {
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
        var out: [ImportableExtension] = []
        for profile in profiles {
            let dir = userData.appendingPathComponent(profile, isDirectory: true)
            for e in extensions(inProfile: dir) {
                if let i = out.firstIndex(where: { $0.id == e.id }) {
                    out[i].profiles[profile] = e.isEnabled
                    out[i].isEnabled = out[i].isEnabled || e.isEnabled
                } else {
                    var e = e
                    e.profiles = [profile: e.isEnabled]
                    out.append(e)
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The profile's pinned extensions (Chromium's extensions.pinned_extensions), in toolbar order.
    static func pinnedIDs(inProfile dir: URL) -> [String]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("Preferences")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["extensions"] as? [String: Any])?["pinned_extensions"] as? [String]
    }

    /// extensions.settings by extension ID, from the profile's files. Newer Chromium keeps
    /// extension state in Secure Preferences; older in Preferences.
    static func settings(inProfile dir: URL) -> [String: Any] {
        var settings: [String: Any] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ext = root["extensions"] as? [String: Any],
                  let s = ext["settings"] as? [String: Any] else { continue }
            settings.merge(s) { _, new in new }
        }
        return settings
    }

    /// Chromium's DISABLE_UNSUPPORTED_MANIFEST_VERSION: Chrome 139 and later turn every
    /// Manifest V2 extension off with it. Cra runs them (GitHub #228), so it doesn't count.
    static let unsupportedManifestVersion = 1 << 23

    private static func isDisabled(_ s: [String: Any]) -> Bool {
        if let reasons = s["disable_reasons"] as? [Any], !reasons.isEmpty {
            return reasons.contains { ($0 as? Int) != unsupportedManifestVersion }
        }
        return (s["state"] as? Int) == 0
    }

    /// Extensions turned off in this profile (chrome://extensions), of any install location:
    /// also the --load-extension ones (location 8), which Chromium loads disabled again.
    static func disabledIDs(inProfile dir: URL) -> Set<String> { disabledIDs(settings: settings(inProfile: dir)) }

    static func disabledIDs(settings: [String: Any]) -> Set<String> {
        Set(settings.compactMap { id, value in (value as? [String: Any]).flatMap { isDisabled($0) ? id : nil } })
    }

    static func extensions(inProfile dir: URL) -> [ImportableExtension] { extensions(settings: settings(inProfile: dir), inProfile: dir) }

    /// The profile's extensions.settings, from its files or (Cra's own profiles) live from Chromium.
    static func extensions(settings: [String: Any], inProfile dir: URL) -> [ImportableExtension] {
        settings.compactMap { id, value -> ImportableExtension? in
            guard let s = value as? [String: Any], let location = s["location"] as? Int,
                  importableLocations.contains(location), let path = s["path"] as? String else { return nil }
            let folder = path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                : dir.appendingPathComponent("Extensions", isDirectory: true).appendingPathComponent(path, isDirectory: true)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            // Themes and hosted apps are not extensions people pick in a toolbar.
            if manifest["theme"] != nil || manifest["app"] != nil { return nil }
            return ImportableExtension(id: id, name: localized(manifest["name"] as? String ?? id, manifest: manifest, folder: folder),
                                       version: manifest["version"] as? String ?? "", folder: folder,
                                       isEnabled: !isDisabled(s), icon: icon(manifest: manifest, folder: folder))
        }
    }

    /// Descriptions are optional: Settings omits an unresolved message key instead of displaying it.
    static func localizedDescription(manifest: [String: Any], folder: URL) -> String {
        let value = localized(manifest["description"] as? String ?? "", manifest: manifest, folder: folder)
        return value.hasPrefix("__MSG_") && value.hasSuffix("__") ? "" : value
    }

    /// Resolves `__MSG_key__` from the extension's default locale.
    static func localized(_ value: String, manifest: [String: Any], folder: URL) -> String {
        guard value.hasPrefix("__MSG_"), value.hasSuffix("__") else { return value }
        let key = String(value.dropFirst(6).dropLast(2)).lowercased()
        let locales = [manifest["default_locale"] as? String, "en", "en_US"].compactMap { $0 }
        for locale in locales {
            let url = folder.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: url),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (k, v) in messages where k.lowercased() == key {
                if let m = (v as? [String: Any])?["message"] as? String { return m }
            }
        }
        return value
    }

    /// The smallest manifest icon of at least `minPixels`, else the largest.
    static func icon(manifest: [String: Any], folder: URL, minPixels: Int = 48) -> NSImage? {
        guard let icons = manifest["icons"] as? [String: String] else { return nil }
        let sized = icons.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        guard let pick = sized.first(where: { $0.0 >= minPixels }) ?? sized.last else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(pick.1))
    }

    /// The manifest icons Chromium draws at `points` on 1x and 2x screens, in one image of that
    /// size: AppKit draws whichever file suits the screen. One 16 px file drawn on a Retina screen
    /// was twice its size and blurred (GitHub #349).
    static func icon(manifest: [String: Any], folder: URL, points: Int) -> NSImage? {
        guard let icons = manifest["icons"] as? [String: String] else { return nil }
        var image: NSImage?
        for file in ExtensionIcons.files(icons, points: points) {
            guard let loaded = NSImage(contentsOf: folder.appendingPathComponent(file)) else { continue }
            for rep in loaded.representations {
                // The first file's shape sets the image's; a square icon is points × points.
                let aspect = rep.pixelsWide > 0 && rep.pixelsHigh > 0 ? Double(rep.pixelsHigh) / Double(rep.pixelsWide)
                    : loaded.size.width > 0 ? loaded.size.height / loaded.size.width : 1
                let size = image?.size ?? NSSize(width: Double(points), height: Double(points) * aspect)
                if image == nil { image = NSImage(size: size) }
                rep.size = size
                image?.addRepresentation(rep)
            }
        }
        return image
    }
}
