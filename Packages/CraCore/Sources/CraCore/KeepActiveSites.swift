import Foundation

/// One entry of "Always keep these sites active" (GitHub #458): Arc's and Chrome's list at
/// arc://settings/performance, the sites whose pages tab sleeping never closes and never freezes.
/// Chrome reads `example.com` as the site and its subdomains and `.example.com` as that address
/// only (url_matcher's filter format); Cra keeps the two apart as a switch, and reads both forms
/// when they are typed.
public struct KeepActiveSite: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    /// What the user typed or picked: a host, or anything `parse` reads one from.
    public var host: String
    /// `app.example.com` counts for `example.com`; never `notexample.com` or `example.com.other.test`.
    public var includesSubdomains: Bool

    public init(id: UUID = UUID(), host: String, includesSubdomains: Bool = true) {
        self.id = id
        self.host = host
        self.includesSubdomains = includesSubdomains
    }

    private enum CodingKeys: String, CodingKey { case id, host, includesSubdomains }

    /// An entry written by hand with only its host still loads, with its subdomains.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        host = try c.decode(String.self, forKey: .host)
        includesSubdomains = (try? c.decodeIfPresent(Bool.self, forKey: .includesSubdomains)) ?? true
    }

    /// The host `text` names and whether it asks for its subdomains itself (`*.` or `[*.]` before it: yes;
    /// Chrome's `.` before it: no; nil when it doesn't say). A URL, a port or a path is read down to
    /// its host. nil when there is no host.
    public static func parse(_ text: String) -> (host: String, includesSubdomains: Bool?)? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var subdomains: Bool?
        if s.hasPrefix("[*.]") {
            s.removeFirst(4)
            subdomains = true
        } else if s.hasPrefix("*.") {
            s.removeFirst(2)
            subdomains = true
        } else if s.hasPrefix(".") {
            s.removeFirst()
            subdomains = false
        }
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace || $0 == "*" }) else { return nil }
        guard let host = URL(string: s.contains("://") ? s : "https://" + s)?.host(percentEncoded: false)?.lowercased() else { return nil }
        var h = host
        while h.hasSuffix(".") { h.removeLast() }
        guard !h.isEmpty, !h.hasPrefix(".") else { return nil }
        return (h, subdomains)
    }

    /// An IP address has no subdomains: `0.0.1` must not count for `127.0.0.1`.
    private static func isAddress(_ host: String) -> Bool {
        host.contains(":") || host.split(separator: ".").allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// The host the entry stands for, as `parse` reads it.
    public var normalizedHost: String? { Self.parse(host)?.host }

    /// Whether `pageHost` (a page's URL host) is this entry's.
    public func matches(host pageHost: String) -> Bool {
        guard let rule = Self.parse(host) else { return false }
        var page = pageHost.lowercased()
        while page.hasSuffix(".") { page.removeLast() }
        if page == rule.host { return true }
        let subdomains = rule.includesSubdomains ?? includesSubdomains
        return subdomains && !Self.isAddress(rule.host) && page.hasSuffix("." + rule.host)
    }

    /// Whether a page at `url` is this entry's. Pages with no host (files, blank pages) never are.
    public func matches(url: String) -> Bool {
        guard let h = URL(string: url)?.host(percentEncoded: false), !h.isEmpty else { return false }
        return matches(host: h)
    }

    /// The entry in Chrome's filter format, as its "Always keep these sites active" stores it:
    /// `example.com` with subdomains, `.example.com` that address only, an IP address as itself.
    public var chromePattern: String? {
        guard let parsed = Self.parse(host) else { return nil }
        let subdomains = parsed.includesSubdomains ?? includesSubdomains
        return subdomains || Self.isAddress(parsed.host) ? parsed.host : "." + parsed.host
    }

    /// The scope as the list shows it.
    public var scopeLabel: String {
        (Self.parse(host)?.includesSubdomains ?? includesSubdomains) ? "and its subdomains" : "this address only"
    }
}

extension AppSettings {
    /// Whether tab sleeping and freezing leave a page at `url` alone (GitHub #458).
    public func keepsActive(url: String) -> Bool {
        !keepActiveSites.isEmpty && keepActiveSites.contains { $0.matches(url: url) }
    }

    /// Adds `text` (a host or an address) to the list, with its subdomains unless it says
    /// otherwise. Returns the entry, or nil when `text` names no host or the list already
    /// has that host with that scope.
    @discardableResult
    public mutating func addKeepActiveSite(_ text: String, includesSubdomains: Bool = true) -> KeepActiveSite? {
        guard let parsed = KeepActiveSite.parse(text) else { return nil }
        let site = KeepActiveSite(host: parsed.host, includesSubdomains: parsed.includesSubdomains ?? includesSubdomains)
        guard !keepActiveSites.contains(where: { $0.normalizedHost == site.host && $0.scopeLabel == site.scopeLabel }) else { return nil }
        keepActiveSites.append(site)
        return site
    }

    /// Chrome's `performance_tuning.tab_discarding.exceptions_with_time` for this list: each
    /// pattern with the time it was added, as base::TimeToValue writes it. Chromium's own freezing
    /// (InfiniteTabsFreezing) reads it, so a listed site isn't frozen behind Cra's back. Patterns
    /// already in `current` keep their time; new ones get `now`. nil when `current` already holds
    /// exactly these patterns.
    public func chromeDiscardExceptions(current: [String: Any], now: Date) -> [String: String]? {
        let patterns = Set(keepActiveSites.compactMap(\.chromePattern))
        guard patterns != Set(current.keys) else { return nil }
        let stamp = String(Int64((now.timeIntervalSince1970 + Self.windowsEpochOffset) * 1_000_000))
        return Dictionary(uniqueKeysWithValues: patterns.map { ($0, current[$0] as? String ?? stamp) })
    }

    /// chrome://settings/performance (Settings ▸ Advanced ▸ More Settings…) edits the same list in
    /// one profile: patterns it added since Cra last wrote `lastWritten` join Cra's list, and the
    /// ones it removed leave it. Returns whether the list changed.
    @discardableResult
    public mutating func adoptChromeEdits(current: Set<String>, lastWritten: Set<String>) -> Bool {
        let before = keepActiveSites
        let removed = lastWritten.subtracting(current)
        keepActiveSites.removeAll { $0.chromePattern.map(removed.contains) == true }
        for pattern in current.subtracting(lastWritten).sorted() { addKeepActiveSite(pattern) }
        return keepActiveSites != before
    }

    /// Seconds from 1601-01-01 (base::Time's epoch) to 1970-01-01.
    static let windowsEpochOffset: TimeInterval = 11_644_473_600

    /// When the list closes: each entry as its host alone (`*.` and `.` become the switch), and
    /// the ones that name no host, or repeat one above them, gone.
    public mutating func tidyKeepActiveSites() {
        var seen = Set<String>()
        keepActiveSites = keepActiveSites.compactMap { site in
            guard let parsed = KeepActiveSite.parse(site.host) else { return nil }
            let subdomains = parsed.includesSubdomains ?? site.includesSubdomains
            guard seen.insert("\(parsed.host) \(subdomains)").inserted else { return nil }
            return KeepActiveSite(id: site.id, host: parsed.host, includesSubdomains: subdomains)
        }
    }
}
