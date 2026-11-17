import CraCEF
import CraCore
import Foundation

/// Settings ▸ Tabs ▸ "Always keep these sites active" (GitHub #458) and Chrome's list of the same
/// name, the one arc://settings/performance edits in Arc and chrome://settings/performance in Cra
/// (Settings ▸ Advanced ▸ More Settings…), kept as one list. Cra's tab sleeping and its freezing
/// vote read Cra's setting; Chromium's own freezing past the five tabs used last
/// (InfiniteTabsFreezing) reads the pref, so without it a listed site would still be frozen.
/// Cra's setting is the one kept across launches; an edit on Chrome's page while Cra runs joins it.
@MainActor
enum ChromeKeepActiveSites {
    static let pref = "performance_tuning.tab_discarding.exceptions_with_time"

    /// What Cra last wrote to each profile's pref this run (Default under ""), so a change made on
    /// Chrome's page can be told from the list Cra wrote.
    private static var written: [String: Set<String>] = [:]

    /// Takes in what Chrome's page changed, then writes the list to each loaded profile whose pref
    /// differs. Run when the setting changes and on each minute's tab-sleeping pass, which reaches a
    /// profile that loaded since and an edit on Chrome's page.
    static func apply(store: SidebarStore) {
        let paths: [String?] = [nil] + store.profiles.map {
            AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path
        }
        for path in paths where CraCEFRuntime.loadState(ofProfile: path) == 2 {
            let current = CraCEFRuntime.preference(pref, forProfile: path)
                .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
            let key = path ?? ""
            if let last = written[key], last != Set(current.keys),
               store.settings.adoptChromeEdits(current: Set(current.keys), lastWritten: last) {
                CraLog.note("keep sites active: took in an edit from Chrome's settings page")
            }
            guard let wanted = store.settings.chromeDiscardExceptions(current: current, now: Date()) else {
                written[key] = Set(current.keys)
                continue
            }
            guard let data = try? JSONSerialization.data(withJSONObject: wanted, options: .sortedKeys),
                  let json = String(data: data, encoding: .utf8) else { continue }
            if CraCEFRuntime.setPreference(pref, json: json, forProfile: path) {
                written[key] = Set(wanted.keys)
            } else {
                CraLog.note("keep sites active: Chromium refused the list for a profile")
            }
        }
    }
}
