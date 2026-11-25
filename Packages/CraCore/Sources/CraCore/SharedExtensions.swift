import Foundation

/// shared-extensions.json (GitHub discussion #595): Chrome Web Store extensions shared from Settings ▸ Extensions.
///
/// A shared extension belongs in every Cra profile but the ones the person took it out of, profiles made later
/// included. Each profile gets the store's own install (Cra installs it the way the store's "Add to Chrome" does,
/// so it updates), and keeps its own settings and data for it, as Arc keeps extensions per profile. Chrome keeps it
/// installed where it belongs (Cra's management policy: chrome://extensions says "Managed by Cra" and has no
/// Remove), so removing it or changing its profiles happens in Cra's Settings. An extension nobody shared stays
/// one profile's own, managed in chrome://extensions as before.
///
/// `{"shared": {"<id>": {"excluded": ["Profile <uuid>"]}}, "removals": {"Profile <uuid>": ["<id>"]}}`
public struct SharedExtensions: Codable, Equatable, Sendable {
    public struct Share: Codable, Equatable, Sendable {
        /// Profile folders ("Default", "Profile <uuid>") the person took it out of.
        public var excluded: [String]

        public init(excluded: [String] = []) {
            self.excluded = excluded
        }
    }

    /// By Chromium extension ID.
    public var shared: [String: Share]
    /// Uninstalls still owed, by profile folder: the extension was taken out of a profile that hadn't loaded, and a
    /// profile's extensions can only be removed once it has. One that's done goes (`settle`), so an install the
    /// person makes there later is left alone.
    public var removals: [String: [String]]

    public init(shared: [String: Share] = [:], removals: [String: [String]] = [:]) {
        self.shared = shared
        self.removals = removals
    }

    public var isEmpty: Bool { shared.isEmpty && removals.isEmpty }

    public func isShared(_ id: String) -> Bool { shared[id] != nil }

    /// The profiles a shared extension belongs in, in `allProfiles` order; none when it isn't shared.
    public func profiles(of id: String, allProfiles: [String]) -> [String] {
        guard let share = shared[id] else { return [] }
        return allProfiles.filter { !share.excluded.contains($0) }
    }

    /// The extensions Chrome keeps installed in each profile (CraCEFRuntime.setManagedExtensionIDs): the shared
    /// ones that belong there. A profile with none is left out.
    public func managedIDs(allProfiles: [String]) -> [String: [String]] {
        var byProfile: [String: [String]] = [:]
        for profile in allProfiles {
            let ids = shared.filter { !$0.value.excluded.contains(profile) }.keys.sorted()
            if !ids.isEmpty { byProfile[profile] = ids }
        }
        return byProfile
    }

    public struct Plan: Equatable, Sendable {
        /// Shared extensions to install from the store there.
        public var install: [String]
        /// Extensions owed an uninstall there.
        public var uninstall: [String]

        public init(install: [String] = [], uninstall: [String] = []) {
            self.install = install
            self.uninstall = uninstall
        }

        public var isEmpty: Bool { install.isEmpty && uninstall.isEmpty }
    }

    /// What a loaded profile that holds `installed` (extension IDs, any install location) needs: the shared
    /// extensions that belong there and it lacks, except where the store already said no (#491), and the removals
    /// owed there that it still has.
    public func plan(profile: String, installed: Set<String>, refused: WebStoreRefusals = WebStoreRefusals()) -> Plan {
        let install = shared.filter { id, share in
            !share.excluded.contains(profile) && !installed.contains(id) && !refused.isRefused(folder: id, inProfile: profile)
        }.keys.sorted()
        // One shared there again since is left alone (setIncluded drops it, this makes sure).
        let owed = (removals[profile] ?? []).filter { id in
            installed.contains(id) && !profiles(of: id, allProfiles: [profile]).contains(profile)
        }
        return Plan(install: install, uninstall: owed.sorted())
    }

    /// Shares `id` with every profile. Sharing it again after it was taken out of profiles puts it back in them.
    /// True when anything changed.
    @discardableResult
    public mutating func share(_ id: String) -> Bool {
        let before = self
        shared[id] = Share()
        for profile in Array(removals.keys) { dropRemoval(id, profile: profile) }
        return self != before
    }

    /// Whether the person may take `id` out of `profile`: not out of the last profile it is in (that is Remove).
    public func canExclude(_ id: String, profile: String, allProfiles: [String]) -> Bool {
        let inProfiles = profiles(of: id, allProfiles: allProfiles)
        return inProfiles.contains(profile) && inProfiles.count > 1
    }

    /// Puts a shared extension in `profile` or takes it out. Taking it out owes an uninstall there; putting it back
    /// cancels one still owed. True when anything changed.
    @discardableResult
    public mutating func setIncluded(_ id: String, profile: String, _ included: Bool) -> Bool {
        guard var share = shared[id] else { return false }
        let before = self
        if included {
            share.excluded.removeAll { $0 == profile }
            dropRemoval(id, profile: profile)
        } else if !share.excluded.contains(profile) {
            share.excluded = (share.excluded + [profile]).sorted()
            removals[profile] = Array(Set((removals[profile] ?? []) + [id])).sorted()
        }
        shared[id] = share
        return self != before
    }

    /// Stops sharing `id`: it stays installed where it is, each install that profile's own again (chrome://extensions
    /// manages it). Uninstalls already owed stay owed. True when it was shared.
    @discardableResult
    public mutating func stopSharing(_ id: String) -> Bool {
        shared.removeValue(forKey: id) != nil
    }

    /// Removes a shared extension from every profile: it stops being shared, and each profile owes its uninstall
    /// until it has loaded and removed it.
    public mutating func removeEverywhere(_ id: String, allProfiles: [String]) {
        shared[id] = nil
        for profile in allProfiles {
            removals[profile] = Array(Set((removals[profile] ?? []) + [id])).sorted()
        }
    }

    /// A loaded profile holds `installed` now: removals owed there that it no longer has are done. True when
    /// anything changed.
    @discardableResult
    public mutating func settle(profile: String, installed: Set<String>) -> Bool {
        guard let owed = removals[profile] else { return false }
        let left = owed.filter { installed.contains($0) }
        guard left != owed else { return false }
        removals[profile] = left.isEmpty ? nil : left
        return true
    }

    private mutating func dropRemoval(_ id: String, profile: String) {
        guard let owed = removals[profile], owed.contains(id) else { return }
        let left = owed.filter { $0 != id }
        removals[profile] = left.isEmpty ? nil : left
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shared = try c.decodeIfPresent([String: Share].self, forKey: .shared) ?? [:]
        removals = try c.decodeIfPresent([String: [String]].self, forKey: .removals) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shared, forKey: .shared)
        if !removals.isEmpty { try c.encode(removals, forKey: .removals) }
    }

    private enum CodingKeys: String, CodingKey { case shared, removals }

    // MARK: What Settings says

    /// The line under an extension in Settings ▸ Extensions: which profiles have it, which the discussion found
    /// missing. `installedIn` nil is every profile (a folder of Cra's that loads everywhere); `names` gives each
    /// profile folder its name, `allProfiles` the order.
    public func profilesLine(id: String, installedIn: Set<String>?, allProfiles: [String], names: [String: String]) -> String {
        let name = { (folder: String) in names[folder] ?? folder }
        guard isShared(id) else {
            let inProfiles = installedIn.map { set in allProfiles.filter(set.contains) + set.subtracting(allProfiles).sorted() } ?? allProfiles
            if allProfiles.count > 1, Set(allProfiles).isSubset(of: Set(inProfiles)) { return "In every profile" }
            return inProfiles.isEmpty ? "In no profile" : "In " + Self.joined(inProfiles.map(name))
        }
        let targets = profiles(of: id, allProfiles: allProfiles)
        var line = targets.count == allProfiles.count ? "Shared with every profile" : "Shared with " + Self.joined(targets.map(name))
        let missing = targets.filter { !(installedIn?.contains($0) ?? true) }
        if !missing.isEmpty {
            line += " · " + Self.joined(missing.map(name)) + (missing.count == 1 ? " gets it when one of its spaces opens"
                                                                                : " get it when one of their spaces opens")
        }
        return line
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}

/// What Remove says it will do (#695, discussion #595): Chromium uninstalls a profile's own install from the page's
/// profile only, Cra deletes its own copy for every profile that loads it, and a shared extension goes from every
/// profile.
public enum ExtensionRemoval {
    public static func message(isShared: Bool, isCraCopy: Bool, profileCount: Int?) -> String {
        if isShared { return "It is shared, so it will be removed from every profile, each with its data." }
        if isCraCopy, profileCount.map({ $0 > 1 }) ?? true { return "It will be removed from every profile that has it." }
        return "It will be removed from this profile, with its data."
    }
}
