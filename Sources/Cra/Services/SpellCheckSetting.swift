import CraCEF
import Foundation

/// Settings ▸ Profiles ▸ "Check spelling while typing" (#715): Chromium's per-profile
/// browser.enable_spellchecking (CraCore SpellCheck), read live or from the profile's Preferences
/// file, written while the profile is loaded.
enum SpellCheckSetting {
    /// `profilePath`: the Chromium profile folder, nil for Default.
    static func isOn(profilePath: String?) -> Bool {
        if let json = CraCEFRuntime.preference(SpellCheck.pref, forProfile: profilePath) { return SpellCheck.isOn(prefJSON: json) }
        let folder = profilePath.map { URL(fileURLWithPath: $0) } ?? AppPaths.chromiumCache.appendingPathComponent("Default")
        return (try? Data(contentsOf: folder.appendingPathComponent("Preferences"))).map(SpellCheck.isOn(preferencesFile:)) ?? true
    }

    /// False when Chromium hasn't loaded the profile (no space uses it yet).
    @discardableResult
    static func set(_ on: Bool, profilePath: String?) -> Bool {
        let ok = CraCEFRuntime.setPreference(SpellCheck.pref, json: SpellCheck.json(on: on), forProfile: profilePath)
        CraLog.note("spell check \(on ? "on" : "off") in \(profilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Default"): \(ok ? "set" : "not loaded")")
        return ok
    }
}
