import Foundation

/// Chromium as ExtensionStore sees it: each loaded profile's extensions.settings (keyed "Default" or the profile's
/// path), and what the store asks of the engine (shared extensions, discussion #595). An uninstall takes the extension
/// out of that profile's settings, as Chromium does.
@MainActor
@objc public final class CraCEFRuntime: NSObject {
    public static var settingsByProfile: [String: String] = [:]
    /// What setManagedExtensionIDs last got.
    public static var managed: [String: [String]] = [:]
    /// Store installs asked for: extension ID and profile key.
    public static var installs: [(id: String, profile: String)] = []

    public static func setExtensionSettingsChangeHandler(_ handler: @escaping () -> Void) {}
    public static func extensionSettings(forProfile profile: String?) -> String? { settingsByProfile[profile ?? "Default"] }

    @objc public static func setManagedExtensionIDs(_ ids: [String: [String]]) { managed = ids }
    /// What setSharedExtensionStorage last got (discussion #595's follow-up), and the switches asked for.
    public static var storage: [String: [String: Any]] = [:]
    public static var switched: [(id: String, on: Bool, profile: String)] = []
    @objc public static func setSharedExtensionStorage(_ homes: [String: [String: Any]]) { storage = homes }
    @objc public static func setExtensionEnabled(_ id: String, enabled: Bool, profilePath: String?) -> Bool {
        switched.append((id, enabled, profilePath ?? "Default"))
        return true
    }
    @objc public static func loadState(ofProfile profile: String?) -> Int { settingsByProfile[profile ?? "Default"] == nil ? 0 : 2 }
    @objc public static func installWebStoreExtension(_ id: String, manifest: String, profilePath: String?,
                                                      completion: @escaping (String?) -> Void) {
        installs.append((id, profilePath ?? "Default"))
        completion("offline in the harness")
    }
    @objc public static func uninstallExtension(_ id: String, profilePath: String?) -> Bool {
        let key = profilePath ?? "Default"
        guard (managed[profileFolder(key)] ?? []).contains(id) == false,
              let json = settingsByProfile[key],
              var settings = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              settings.removeValue(forKey: id) != nil else { return false }
        settingsByProfile[key] = String(decoding: try! JSONSerialization.data(withJSONObject: settings), as: UTF8.self)
        return true
    }

    /// Chrome's management policy is keyed by folder name; the settings by "Default" or path.
    private static func profileFolder(_ key: String) -> String { (key as NSString).lastPathComponent }
}

@MainActor
@objc public final class CraBrowser: NSObject {
    public override init() {}

    public func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {}
    @objc public func uninstallExtension(_ id: String) -> Bool { false }
}
