import Foundation

/// Settings ▸ Extensions in sections (discussion #595's follow-up, Anoninz): "Shared across Profiles" on top, then a
/// group for each profile with the extensions that profile has of its own, then Cra's own copies (unpacked or
/// imported folders Cra loads itself). An extension installed separately in two profiles is a row in each group,
/// removed or shared from its own profile; before, the two installs were one row.
public enum ExtensionsLayout {
    /// One installed extension as Settings knows it.
    public struct Item: Equatable, Sendable {
        public var id: String
        public var name: String
        /// Installed by Chrome into profiles (the Web Store, chrome://extensions' "Load unpacked"); false for Cra's own
        /// copy, which Cra loads into `profiles` (nil: every profile).
        public var installedByChrome: Bool
        public var profiles: Set<String>?

        public init(id: String, name: String, installedByChrome: Bool, profiles: Set<String>?) {
            self.id = id
            self.name = name
            self.installedByChrome = installedByChrome
            self.profiles = profiles
        }
    }

    public enum Kind: Equatable, Sendable {
        /// "Shared across Profiles".
        case shared
        /// A profile's own extensions, by profile folder.
        case profile(String)
        /// Cra's own copies.
        case craCopies
    }

    public struct Row: Equatable, Sendable {
        public var id: String
        /// The profile this row's install is in, nil for a shared extension or Cra's copy.
        public var profile: String?

        public init(id: String, profile: String?) {
            self.id = id
            self.profile = profile
        }
    }

    public struct Section: Equatable, Sendable {
        public var kind: Kind
        public var title: String
        public var rows: [Row]
    }

    /// The sections, in order, leaving out empty ones. Rows go by name, then ID. `names` names each profile folder.
    public static func sections(items: [Item], shares: SharedExtensions, allProfiles: [String],
                                names: [String: String]) -> [Section] {
        let sorted = items.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        var result: [Section] = []
        let shared = sorted.filter { shares.isShared($0.id) }
        if !shared.isEmpty {
            result.append(Section(kind: .shared, title: "Shared across Profiles", rows: shared.map { Row(id: $0.id, profile: nil) }))
        }
        let own = sorted.filter { $0.installedByChrome && !shares.isShared($0.id) }
        for profile in allProfiles {
            let rows = own.filter { $0.profiles?.contains(profile) ?? true }.map { Row(id: $0.id, profile: profile) }
            if !rows.isEmpty { result.append(Section(kind: .profile(profile), title: names[profile] ?? profile, rows: rows)) }
        }
        let copies = sorted.filter { !$0.installedByChrome && !shares.isShared($0.id) }
        if !copies.isEmpty {
            result.append(Section(kind: .craCopies, title: "Added to Cra", rows: copies.map { Row(id: $0.id, profile: nil) }))
        }
        return result
    }

    /// The profiles "Share across Profiles…" lists for an extension set up in `home`: every profile, home first and
    /// always checked; the others checked to start with only when they have it already (they share it now, so it
    /// shows what changes).
    public static func shareChecklist(home: String, allProfiles: [String]) -> [String] {
        [home] + allProfiles.filter { $0 != home }
    }

    /// The line under a shared extension: whose data it uses, when one profile's.
    public static func homeLine(_ id: String, shares: SharedExtensions, names: [String: String]) -> String? {
        guard let home = shares.home(of: id) else { return nil }
        return "Settings and sign-in from \(names[home] ?? home)"
    }
}
