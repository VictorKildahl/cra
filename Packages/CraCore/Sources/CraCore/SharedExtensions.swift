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
///
/// Since the follow-up on discussion #595 (Anoninz, 27 Nov 2026) a share is opt-in and shares the extension's own
/// data: `{"included": ["Default", "Profile <uuid>"], "home": "Default", "off": true}`. `included` names exactly the
/// profiles it is in (profiles made later are not), `home` is the profile it was set up in, whose chrome.storage (local
/// and sync) every included profile reads and writes (the engine routes it; websites' cookies and logins stay each
/// profile's own), and `off` turns it off in all of them at once. A share from before has neither: every profile but
/// the excluded ones, each with its own data.
public struct SharedExtensions: Codable, Equatable, Sendable {
    public struct Share: Codable, Equatable, Sendable {
        /// Profile folders ("Default", "Profile <uuid>") the person took it out of (a share from before the opt-in).
        public var excluded: [String]
        /// The profiles it is in, picked when it was shared (nil: every profile but `excluded`, as shares from before).
        public var included: [String]?
        /// The profile it was set up in: its data is the one every included profile uses (nil: each its own).
        public var home: String?
        /// Turned off in every profile it is in.
        public var off: Bool

        public init(excluded: [String] = [], included: [String]? = nil, home: String? = nil, off: Bool = false) {
            self.excluded = excluded
            self.included = included
            self.home = home
            self.off = off
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            excluded = try c.decodeIfPresent([String].self, forKey: .excluded) ?? []
            included = try c.decodeIfPresent([String].self, forKey: .included)
            home = try c.decodeIfPresent(String.self, forKey: .home)
            off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
        }

        /// A share from before writes what it read: only `excluded`.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if included == nil || !excluded.isEmpty { try c.encode(excluded, forKey: .excluded) }
            try c.encodeIfPresent(included, forKey: .included)
            try c.encodeIfPresent(home, forKey: .home)
            if off { try c.encode(off, forKey: .off) }
        }

        private enum CodingKeys: String, CodingKey { case excluded, included, home, off }

        func contains(_ profile: String) -> Bool {
            included.map { $0.contains(profile) } ?? !excluded.contains(profile)
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
        return allProfiles.filter(share.contains)
    }

    /// The extensions Chrome keeps installed in each profile (CraCEFRuntime.setManagedExtensionIDs): the shared
    /// ones that belong there. A profile with none is left out.
    public func managedIDs(allProfiles: [String]) -> [String: [String]] {
        var byProfile: [String: [String]] = [:]
        for profile in allProfiles {
            let ids = shared.filter { $0.value.contains(profile) }.keys.sorted()
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
            share.contains(profile) && !installed.contains(id) && !refused.isRefused(folder: id, inProfile: profile)
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

    /// Shares `id` from `home`, the profile it was set up in, with exactly `profiles` (home always among them): each
    /// gets the store's install and uses home's data for it (discussion #595's follow-up). Profiles made later don't
    /// get it. True when anything changed.
    @discardableResult
    public mutating func share(_ id: String, from home: String, with profiles: [String]) -> Bool {
        let before = self
        let included = Array(Set(profiles + [home])).sorted()
        shared[id] = Share(included: included, home: home)
        for profile in included { dropRemoval(id, profile: profile) }
        return self != before
    }

    /// The profiles `share(_:from:with:)` would give home's data although they have the extension already, their own
    /// install with their own data, which Settings asks about first. In `profiles`' order, home left out.
    public static func replacedInstalls(home: String, profiles: [String], installedIn: Set<String>) -> [String] {
        profiles.filter { $0 != home && installedIn.contains($0) }
    }

    /// The profile whose data a shared extension uses everywhere, nil when each profile keeps its own.
    public func home(of id: String) -> String? { shared[id]?.home }

    /// Shared extensions whose data comes from one profile, for the engine (CraCEFRuntime.setSharedExtensionStorage):
    /// by extension ID, its home and the profiles that use it (home among them).
    public func storageHomes(allProfiles: [String]) -> [String: (home: String, profiles: [String])] {
        var homes: [String: (home: String, profiles: [String])] = [:]
        for (id, share) in shared {
            guard let home = share.home else { continue }
            homes[id] = (home, profiles(of: id, allProfiles: allProfiles))
        }
        return homes
    }

    /// Whether the person may take `id` out of `profile`: not out of the last profile it is in (that is Remove), and
    /// not out of its home while it is in others: the data they use lives there.
    public func canExclude(_ id: String, profile: String, allProfiles: [String]) -> Bool {
        let inProfiles = profiles(of: id, allProfiles: allProfiles)
        return inProfiles.contains(profile) && inProfiles.count > 1 && shared[id]?.home != profile
    }

    /// Stop Sharing is offered once one profile is left: that profile keeps the extension as its own, with the data
    /// it was using (the home's, which is that profile's own). With more, the person takes the others out first, so
    /// nobody's data has to be guessed.
    public func canStopSharing(_ id: String, allProfiles: [String]) -> Bool {
        isShared(id) && profiles(of: id, allProfiles: allProfiles).count <= 1
    }

    /// Whether a shared extension is on (in every profile it is in) or off (in all of them).
    public func isOn(_ id: String) -> Bool { !(shared[id]?.off ?? false) }

    /// Turns a shared extension on or off in all its profiles. True when anything changed.
    @discardableResult
    public mutating func setOn(_ id: String, _ on: Bool) -> Bool {
        guard var share = shared[id], share.off == on else { return false }
        share.off = !on
        shared[id] = share
        return true
    }

    /// One switch for a shared extension: Chrome says which of its profiles have it turned off now (`offIn`), and in
    /// which the switch changed since Cra last looked (`changed`: the person used chrome://extensions there). A change
    /// is the shared state for every profile it is in; otherwise each loaded profile follows the shared state (one that
    /// has just loaded, say). Returns the state and the profiles Chrome must switch (profile → on). Profiles that
    /// haven't loaded aren't in `loaded`: they follow as they load.
    public mutating func followSwitch(_ id: String, offIn: Set<String>, changed: Set<String> = [], loaded: [String],
                                      allProfiles: [String]) -> (on: Bool, apply: [String: Bool]) {
        guard isShared(id) else { return (true, [:]) }
        let members = profiles(of: id, allProfiles: allProfiles).filter(loaded.contains)
        var on = isOn(id)
        if let flipped = members.first(where: { changed.contains($0) && offIn.contains($0) == on }) {
            on = !offIn.contains(flipped)
        }
        setOn(id, on)
        var apply: [String: Bool] = [:]
        for profile in members where offIn.contains(profile) == on { apply[profile] = on }
        return (on, apply)
    }

    /// Puts a shared extension in `profile` or takes it out. Taking it out owes an uninstall there; putting it back
    /// cancels one still owed. True when anything changed.
    @discardableResult
    public mutating func setIncluded(_ id: String, profile: String, _ included: Bool) -> Bool {
        guard var share = shared[id] else { return false }
        let before = self
        if included {
            share.excluded.removeAll { $0 == profile }
            if let list = share.included, !list.contains(profile) { share.included = (list + [profile]).sorted() }
            dropRemoval(id, profile: profile)
        } else if share.contains(profile) {
            if let list = share.included { share.included = list.filter { $0 != profile } }
            else { share.excluded = (share.excluded + [profile]).sorted() }
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

    /// The profiles whose chrome://extensions page can remove a Web Store extension that isn't shared (#842):
    /// Chrome uninstalls a profile's own install from that profile's page only, so Settings opens the page there,
    /// not in the space it was opened from. Two or more: Remove… asks which, in Settings' profile order. A folder
    /// no profile of Cra's owns any more has no page to open; `installedIn` nil is every profile.
    public static func pageProfiles(installedIn: Set<String>?, allProfiles: [String]) -> [String] {
        allProfiles.filter { installedIn?.contains($0) ?? true }
    }

    /// The profile Chrome uninstalls from when a pinned extension's menu says Remove: the profile the menu is for
    /// (the toolbar or sidebar its button is in), not the window's current page, which can be on another profile
    /// (another window's toolbar, a space on another profile). Nil when that profile doesn't have it: Chrome CHECKs
    /// an uninstall of an extension the profile doesn't know (crash-extension-remove-other-profile). `installedIn`
    /// nil is every profile.
    public static func engineProfile(menuProfile: String, installedIn: Set<String>?) -> String? {
        installedIn.map { $0.contains(menuProfile) } ?? true ? menuProfile : nil
    }
}
