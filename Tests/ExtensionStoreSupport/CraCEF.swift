import Foundation

@MainActor
public enum CraCEFRuntime {
    public static var settingsByProfile: [String: String] = [:]
    public static func setExtensionSettingsChangeHandler(_ handler: @escaping () -> Void) {}
    public static func extensionSettings(forProfile profile: String?) -> String? { settingsByProfile[profile ?? "Default"] }
}

@MainActor
public final class CraBrowser {
    public init() {}

    public func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {}
}
