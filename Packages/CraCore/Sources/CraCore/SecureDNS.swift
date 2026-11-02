import Foundation

/// Chromium's secure DNS setting (chrome://settings/security), one value for the whole app in
/// Local State. Cra leaves it on Chromium's default as Arc does: "automatic" with no provider,
/// which is the system resolver, encrypted only when that resolver is a known DoH server. So a
/// work network's own DNS keeps resolving its internal names (#110). The log and Export
/// Diagnostics say what is in effect.
public struct SecureDNS: Equatable, Sendable {
    /// dns_over_https.mode: "off", "automatic" or "secure"; empty when nothing set it.
    public var mode: String
    /// The DoH servers' hosts, from dns_over_https.templates. Only hosts: a custom template's
    /// path can carry the user's own resolver profile (NextDNS puts an id there).
    public var servers: [String]

    public init(mode: String, templates: String) {
        self.mode = mode
        var hosts: [String] = []
        for template in templates.split(whereSeparator: \.isWhitespace) {
            // "{?dns}" and other RFC 6570 parts aren't valid in a URL.
            let base = template.prefix { $0 != "{" }
            let host = URLComponents(string: String(base))?.host.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "a custom server"
            if !hosts.contains(host) { hosts.append(host) }
        }
        servers = hosts
    }

    /// "automatic, no provider (system resolver)", "secure via dns.google", "off"
    public var line: String {
        switch mode {
        case "off": return "off"
        case "": return "unset"
        default:
            if servers.isEmpty { return "\(mode), no provider\(mode == "automatic" ? " (system resolver)" : "")" }
            return "\(mode) via \(servers.joined(separator: ", "))"
        }
    }
}
