import CraCEF
import CraCore
import Foundation

/// Arc's Settings ▸ Advanced ▸ "Reset Translated-site Prompts": the sites and languages you chose always or never
/// to translate are forgotten, so Chromium offers to translate again (TranslateReset names what). In Cra those
/// are Chromium's translate preferences, one set per profile, and the reset reaches every profile: a loaded one
/// through Chromium, one being loaded once it has, one not loaded this session in its Preferences file.
@MainActor
enum TranslatedSitePrompts {
    /// Chromium's dated list of the sites "Never Translate This Site" put on it.
    private static let neverSites = "translate_site_blocklist_with_time"
    private static let blockedLanguages = "translate_blocked_languages"
    /// Profiles whose prefs were being read when the reset ran: reset as each finishes loading.
    private static var pendingProfiles: Set<String> = []

    /// Resets the translate choices of Default and every other profile. Returns how many profiles it reached
    /// now (a loading one is reset when it has loaded).
    @discardableResult
    static func reset(store: SidebarStore) -> Int {
        var reached = 0
        for (_, path) in profiles(store) {
            switch CraCEFRuntime.loadState(ofProfile: path) {
            case 2:
                resetLoaded(path)
                reached += 1
            case 1:
                if let path { pendingProfiles.insert(path) }
                CraCEFRuntime.setProfileLoadedHandler { path in
                    MainActor.assumeIsolated {
                        guard pendingProfiles.remove(path) != nil else { return }
                        resetLoaded(path)
                        CraLog.note("translate prompts reset: profile loaded and reset")
                    }
                }
            default:
                if let path, resetFile(of: path) { reached += 1 }
            }
        }
        CraLog.note("translate prompts reset: \(reached) profiles reset, \(pendingProfiles.count) when loaded")
        return reached
    }

    /// Each choice back to Chromium's default, as TranslatePrefs::ResetToDefaults clears it.
    private static func resetLoaded(_ path: String?) {
        for name in TranslateReset.preferences { CraCEFRuntime.resetPreference(name, forProfile: path) }
    }

    /// A profile no one has asked for this session: nothing in Cra has its Preferences file open, and Chromium
    /// reads it when the profile loads. Written whole, so a load never reads half a file. False when the file
    /// isn't there (the profile never loaded) or holds no choice.
    private static func resetFile(of path: String) -> Bool {
        let file = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("Preferences")
        guard let data = try? Data(contentsOf: file), let reset = TranslateReset.resettingPreferencesFile(data) else { return false }
        do {
            try reset.write(to: file, options: .atomic)
            return true
        } catch {
            CraLog.fault("translate prompts reset: can't write a profile's Preferences: \(error.localizedDescription)")
            return false
        }
    }

    /// Default (nil) first, then the profiles Cra made, as CraCEFRuntime names them.
    private static func profiles(_ store: SidebarStore) -> [(name: String, path: String?)] {
        [("Default", nil)] + store.profiles.map {
            ($0.name, AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path)
        }
    }

    /// Scenario readout (`cra://debug?translatePrompts=…&label=…`, `&profile=<name>` for another profile than Default):
    /// `never:<host>` puts a site on the never-translate list as "Never Translate This Site" does, `block:<lang>`
    /// adds a language to never translate, `reset` is the Settings button. Then each profile's never-translate
    /// sites and never-translate languages, live or from its file, and whether it has loaded.
    static func debug(_ command: String, profile: String?, label: String, store: SidebarStore) {
        let all = profiles(store)
        let path = all.first { $0.name == (profile ?? "Default") }?.path ?? nil
        if command.hasPrefix("never:") {
            let host = String(command.dropFirst("never:".count))
            let json = (try? JSONSerialization.data(withJSONObject: [host: "13345678901234567"])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let ok = CraCEFRuntime.setPreference(neverSites, json: json, forProfile: path)
            CraLog.note("translate prompts: never \(host) \(ok ? "set" : "refused")")
        } else if command.hasPrefix("block:") {
            let current = CraCEFRuntime.preference(blockedLanguages, forProfile: path)
                .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
            let json = (try? JSONSerialization.data(withJSONObject: current + [String(command.dropFirst("block:".count))]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let ok = CraCEFRuntime.setPreference(blockedLanguages, json: json, forProfile: path)
            CraLog.note("translate prompts: block \(command.dropFirst("block:".count)) \(ok ? "set" : "refused")")
        } else if command == "reset" {
            reset(store: store)
        }
        for (name, path) in all {
            let state = CraCEFRuntime.loadState(ofProfile: path)
            var prefs: [String: Any] = [:]
            if state == 2 {
                for key in [neverSites, blockedLanguages] {
                    if let json = CraCEFRuntime.preference(key, forProfile: path),
                       let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) { prefs[key] = value }
                }
            } else if let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Preferences")) {
                prefs = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
            let sites = (prefs[neverSites] as? [String: Any])?.count ?? 0
            let blocked = (prefs[blockedLanguages] as? [String])?.joined(separator: ",") ?? "default"
            let loaded = state == 2 ? "loaded" : state == 1 ? "loading" : "not loaded"
            CraLog.note("translate prompts \(label): \(name) \(loaded) never sites=\(sites) never languages=\(blocked)")
        }
    }
}
