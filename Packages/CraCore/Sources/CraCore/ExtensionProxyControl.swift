import Foundation

/// Which extension's proxy a profile uses (GitHub #107: two proxy extensions collided and
/// nothing said so). An extension's `chrome.proxy.settings.set` lands in its own
/// `extensions.settings.<id>.preferences` (or `regular_only_preferences`) under "proxy", and
/// Chromium applies the one from the most recently installed or updated enabled extension
/// (ExtensionPrefValueMap::GetEffectivePrefValueController: the latest `last_update_time`
/// wins, a tie goes to the later ID). The others get `levelOfControl:
/// "controlled_by_other_extensions"`, which is how ZeroOmega knows to warn.
public enum ExtensionProxyControl {
    public struct Controller: Equatable, Sendable {
        public let extensionID: String
        /// Chromium's `last_update_time`: microseconds since 1601.
        public let installTime: Int64
        /// The proxy it asks for, without addresses beyond a host (see `summary`).
        public let config: String
        /// The proxy servers' and PAC file's hosts, for Export Diagnostics' "Hide site names".
        public let hosts: [String]

        public init(extensionID: String, installTime: Int64, config: String, hosts: [String] = []) {
            self.extensionID = extensionID
            self.installTime = installTime
            self.config = config
            self.hosts = hosts
        }
    }

    /// The extensions in `enabled` that set the proxy for normal pages, the one Chromium applies
    /// first. `settings` is a profile's `extensions.settings`.
    public static func controllers(settings: [String: Any], enabled: Set<String>) -> [Controller] {
        settings.compactMap { id, value -> Controller? in
            guard enabled.contains(id), let s = value as? [String: Any] else { return nil }
            let proxy = ((s["regular_only_preferences"] as? [String: Any])?["proxy"]
                ?? (s["preferences"] as? [String: Any])?["proxy"]) as? [String: Any]
            guard let proxy else { return nil }
            let time = (s["last_update_time"] as? String).flatMap { Int64($0) } ?? (s["last_update_time"] as? NSNumber)?.int64Value ?? 0
            let d = describe(proxy)
            return Controller(extensionID: id, installTime: time, config: d.summary, hosts: d.hosts)
        }
        .sorted { ($0.installTime, $0.extensionID) > ($1.installTime, $1.extensionID) }
    }

    /// A proxy pref (Chromium's ProxyConfigDictionary: mode, server, pac_url, bypass_list) in
    /// a line for the log and the diagnostics: hosts and ports, never a PAC URL's path or an
    /// inline PAC script.
    public static func summary(_ proxy: [String: Any]) -> String { describe(proxy).summary }

    private static func describe(_ proxy: [String: Any]) -> (summary: String, hosts: [String]) {
        let mode = proxy["mode"] as? String ?? "?"
        switch mode {
        case "fixed_servers":
            var hosts: [String] = []
            let servers = (proxy["server"] as? String ?? "").split(separator: ";").map { rule -> String in
                // "http=host:port", "socks5://host:port", "host:port": keep the scheme and host:port.
                let parts = rule.split(separator: "=", maxSplits: 1)
                let target = String(parts.last ?? "")
                let label = parts.count == 2 ? "\(parts[0])=" : ""
                return label + (URLComponents(string: target.contains("://") ? target : "x://" + target).map {
                    let scheme = target.contains("://") ? "\($0.scheme ?? "")://" : ""
                    if let h = $0.host { hosts.append(h) }
                    return scheme + ($0.host ?? "?") + ($0.port.map { ":\($0)" } ?? "")
                } ?? "?")
            }
            return ("fixed_servers " + servers.joined(separator: ";"), hosts)
        case "pac_script":
            guard let url = proxy["pac_url"] as? String, !url.isEmpty, !url.hasPrefix("data:") else { return ("pac_script (inline)", []) }
            let host = URLComponents(string: url)?.host
            return ("pac_script " + (host ?? "?"), host.map { [$0] } ?? [])
        default:
            return (mode, [])
        }
    }
}
