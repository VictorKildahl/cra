import CraCEF
import CraCore
import Foundation

/// Chromium calls each profile what Cra does (GitHub #666), as Arc's Chromium does: Arc keeps its
/// names in Local State's profile list. Cra writes a loaded profile's `profile.name`, which Chromium
/// copies there itself, so chrome:// pages and extensions show "Work", not "Person 2". Run at launch,
/// after a rename and on each minute's pass, which reaches a profile that loaded since.
@MainActor
enum ChromiumProfileNames {
    static func apply(store: SidebarStore) {
        let profiles: [(id: UUID?, path: String?)] = [(nil, nil)] + store.profiles.map {
            ($0.id, AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path)
        }
        for (id, path) in profiles where CraCEFRuntime.loadState(ofProfile: path) == 2 {
            for (pref, json) in ProfileNames.chromiumPrefs(name: store.profileName(id))
            where !same(CraCEFRuntime.preference(pref, forProfile: path), json) {
                if !CraCEFRuntime.setPreference(pref, json: json, forProfile: path) {
                    CraLog.note("profile names: Chromium refused \(pref) for a profile")
                }
            }
        }
    }

    /// The same JSON value however it is escaped (Chromium writes "✨" as "\u2728").
    private static func same(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        let value = { (s: String) in try? JSONSerialization.jsonObject(with: Data(s.utf8), options: .fragmentsAllowed) }
        guard let x = value(a), let y = value(b) else { return a == b }
        return (x as? NSObject)?.isEqual(y) ?? false
    }
}
