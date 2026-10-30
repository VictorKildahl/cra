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
    let isEnabled: Bool
    let icon: NSImage?
}

enum ExtensionImporter {
    /// Chrome's Manifest::Location: 1 internal (Web Store), 4 unpacked. Component
    /// (5) and external installs belong to the browser itself and are skipped.
    private static let importableLocations: Set<Int> = [1, 4]

    static func extensions(inBrowserSupportDir supportDir: URL) -> [ImportableExtension] {
        extensions(inUserData: supportDir.appendingPathComponent("User Data", isDirectory: true))
    }

    /// Every profile under a Chromium "User Data" folder (Chrome, Brave, Edge… keep it at the top level).
    static func extensions(inUserData userData: URL) -> [ImportableExtension] {
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
        var seen = Set<String>()
        var out: [ImportableExtension] = []
        for profile in profiles {
            let dir = userData.appendingPathComponent(profile, isDirectory: true)
            for e in extensions(inProfile: dir) where seen.insert(e.id).inserted { out.append(e) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func extensions(inProfile dir: URL) -> [ImportableExtension] {
        var settings: [String: Any] = [:]
        // Newer Chromium keeps extension state in Secure Preferences; older in Preferences.
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ext = root["extensions"] as? [String: Any],
                  let s = ext["settings"] as? [String: Any] else { continue }
            settings.merge(s) { _, new in new }
        }
        return settings.compactMap { id, value -> ImportableExtension? in
            guard let s = value as? [String: Any], let location = s["location"] as? Int,
                  importableLocations.contains(location), let path = s["path"] as? String else { return nil }
            let folder = path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
                : dir.appendingPathComponent("Extensions", isDirectory: true).appendingPathComponent(path, isDirectory: true)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            // Themes and hosted apps are not extensions people pick in a toolbar.
            if manifest["theme"] != nil || manifest["app"] != nil { return nil }
            let disabled = !((s["disable_reasons"] as? [Any])?.isEmpty ?? true) || (s["state"] as? Int) == 0
            return ImportableExtension(id: id, name: localized(manifest["name"] as? String ?? id, manifest: manifest, folder: folder),
                                       version: manifest["version"] as? String ?? "", folder: folder,
                                       isEnabled: !disabled, icon: icon(manifest: manifest, folder: folder))
        }
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
}
