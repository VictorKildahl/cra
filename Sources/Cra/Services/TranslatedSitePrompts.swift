import CraCEF
import Foundation

/// Arc's Settings ▸ Advanced ▸ "Reset Translated-site Prompts": the sites you chose never to translate and the
/// other translate choices are forgotten, so Chromium offers to translate again (TranslateReset names what).
/// In Cra those are Chromium's translate preferences, one set per profile.
@MainActor
enum TranslatedSitePrompts {
    /// Chromium's dated list of the sites "Never Translate This Site" put on it.
    private static let neverSites = "translate_site_blocklist_with_time"

    /// Empties the translate choices of Default and every other profile that has loaded. Returns how many
    /// preferences held something.
    @discardableResult
    static func reset(store: SidebarStore) -> Int {
        var emptied = 0
        for path in profilePaths(store) {
            for name in TranslateReset.preferences {
                guard let json = CraCEFRuntime.preference(name, forProfile: path), let empty = TranslateReset.emptied(json),
                      CraCEFRuntime.setPreference(name, json: empty, forProfile: path) else { continue }
                emptied += 1
            }
        }
        CraLog.note("translate prompts reset: \(emptied) preferences emptied")
        return emptied
    }

    /// Default (nil) first, then the profiles Cra made, as CraCEFRuntime names them.
    private static func profilePaths(_ store: SidebarStore) -> [String?] {
        [nil] + store.profiles.map { AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path }
    }

    /// Scenario readout (`cra://debug?translatePrompts=…`): `never:<host>` puts a site on Default's never-translate list
    /// as "Never Translate This Site" does, `reset` is the Settings button, `state` says how many sites are on it.
    static func debug(_ command: String, store: SidebarStore) {
        if command.hasPrefix("never:") {
            let host = String(command.dropFirst("never:".count))
            let json = (try? JSONSerialization.data(withJSONObject: [host: 1_700_000_000])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let ok = CraCEFRuntime.setPreference(neverSites, json: json, forProfile: nil)
            CraLog.note("translate prompts: never \(host) \(ok ? "set" : "refused")")
        } else if command == "reset" {
            reset(store: store)
        }
        let json = CraCEFRuntime.preference(neverSites, forProfile: nil)
        let count = json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }?.count
        CraLog.note("translate prompts: never sites=\(count.map(String.init) ?? "unavailable")")
    }
}
