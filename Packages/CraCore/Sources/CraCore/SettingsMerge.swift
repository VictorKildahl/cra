import Foundation

/// Settings from another Mac merged with what changed here since the bundle both Macs had, field by field, as
/// SidebarMerge does the sidebar. A setting changed on one Mac was lost when the other wrote its bundle before
/// iCloud brought it the change: the bundle's settings replaced this Mac's whole (X, 25 Nov 2026, "Archive tabs
/// after" Never on one Mac and 12 hours on the other).
public enum SettingsMerge {
    /// Each field as settings.json holds it: the other Mac's where it changed it, this Mac's otherwise. A field both
    /// changed takes the other Mac's, the later write. Settings that don't round-trip through JSON come back as `remote`,
    /// the old whole replacement.
    public static func merge(base: AppSettings, local: AppSettings, remote: AppSettings) -> AppSettings {
        guard let b = fields(base), let l = fields(local), let r = fields(remote) else { return remote }
        var merged = l
        for key in Set(b.keys).union(r.keys) where !same(b[key], r[key]) {
            for k in together.first(where: { $0.contains(key) }) ?? [key] { merged[k] = r[k] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return remote }
        return settings
    }

    /// Fields that hold one choice between them: 90 or 180 days is "thirtyDays" with autoArchiveDays (#278).
    static let together: [[String]] = [["autoArchive", "autoArchiveDays"]]

    private static func fields(_ settings: AppSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as AnyObject).isEqual(b as AnyObject)
        default: false
        }
    }
}
