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

extension SecureDNS {
    /// The footnote under Settings ▸ Privacy ▸ Secure DNS: what is in effect, from the same
    /// value as `line`, so the pane and cra.log agree.
    public var summary: String {
        let to = servers.joined(separator: ", ")
        switch mode {
        case "": return ""
        case "off": return "Hostnames are looked up in plain text by the network’s own resolver."
        case "secure":
            if servers.isEmpty { return "No provider is set, so hostnames can’t be looked up. Choose one above." }
            return "Hostnames are looked up over an encrypted connection to \(to). If it can’t be reached, pages don’t load."
        default:
            if servers.isEmpty {
                return "Automatic uses the network’s own resolver, encrypted when it supports it. Names only a work network knows keep working."
            }
            return "Hostnames are looked up over an encrypted connection to \(to) when it answers, else by the network’s own resolver."
        }
    }
}

/// A DoH provider in Settings ▸ Privacy ▸ Secure DNS, named and templated as Chromium's
/// net/dns/public/doh_provider_entry.cc has it (chrome://settings/security writes the same
/// template, so a provider picked there shows by name here).
public struct SecureDNSProvider: Hashable, Sendable, Identifiable {
    public let name: String
    public let template: String
    public var id: String { template }

    /// Chrome's providers shown everywhere, plus DNS4EU, which it shows in the EU (named shorter
    /// than Chrome's "DNS4EU Public Service (Protective)", which set the menu's width). NextDNS
    /// needs the user's own profile id in the path, so it goes through Custom.
    public static let all: [SecureDNSProvider] = [
        SecureDNSProvider(name: "Google (Public DNS)", template: "https://dns.google/dns-query{?dns}"),
        SecureDNSProvider(name: "Cloudflare (1.1.1.1)", template: "https://chrome.cloudflare-dns.com/dns-query"),
        SecureDNSProvider(name: "Quad9 (9.9.9.9)", template: "https://dns.quad9.net/dns-query"),
        SecureDNSProvider(name: "OpenDNS", template: "https://doh.opendns.com/dns-query{?dns}"),
        SecureDNSProvider(name: "CleanBrowsing (Family Filter)", template: "https://doh.cleanbrowsing.org/doh/family-filter{?dns}"),
        SecureDNSProvider(name: "DNS4EU (Protective)", template: "https://protective.joindns4.eu/dns-query{?dns}"),
    ]
}

/// The Secure DNS menu's rows.
public enum SecureDNSChoice: Hashable, Sendable {
    /// Chromium's default: the network's own resolver, encrypted when it is a known DoH server.
    case automatic
    case off
    case provider(SecureDNSProvider)
    case custom
}

/// `dns_over_https.mode` and `dns_over_https.templates` as Settings reads and writes them.
/// Local State is the only copy: Cra keeps none, so a fresh install has no key and a choice
/// made in chrome://settings/security shows here too.
public struct SecureDNSPrefs: Equatable, Sendable {
    public var mode: String
    public var templates: String

    public init(mode: String, templates: String) {
        self.mode = mode
        self.templates = templates
    }

    /// What to write for a menu row. Custom takes the typed templates and is nil while they
    /// aren't valid.
    public init?(_ choice: SecureDNSChoice, custom: String = "") {
        switch choice {
        case .automatic: self.init(mode: "automatic", templates: "")
        case .off: self.init(mode: "off", templates: "")
        case .provider(let p): self.init(mode: "secure", templates: p.template)
        case .custom:
            guard let templates = Self.validTemplates(custom) else { return nil }
            self.init(mode: "secure", templates: templates)
        }
    }

    /// The menu row for what Chromium holds. Automatic with a provider (an old Chrome default
    /// or a policy) is still Automatic: the footnote names the provider.
    public var choice: SecureDNSChoice {
        switch mode {
        case "off": return .off
        case "secure":
            let t = templates.trimmingCharacters(in: .whitespacesAndNewlines)
            return SecureDNSProvider.all.first { $0.template == t }.map { .provider($0) } ?? .custom
        default: return .automatic
        }
    }

    /// A custom entry as Chromium takes it: one or more RFC 8484 URI templates separated by
    /// whitespace, each https:// with a host. The path is kept exactly as typed (NextDNS puts
    /// the user's profile id there). nil when any of them isn't one.
    public static func validTemplates(_ text: String) -> String? {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        for template in parts {
            guard template.lowercased().hasPrefix("https://"), isBalanced(template) else { return nil }
            // RFC 6570 expressions ("{?dns}") aren't valid in a URL: check what's before them.
            let base = String(template.prefix { $0 != "{" })
            guard let url = URLComponents(string: base), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        }
        return parts.joined(separator: " ")
    }

    private static func isBalanced(_ template: String) -> Bool {
        var open = false
        for c in template {
            if c == "{" { if open { return false }; open = true }
            if c == "}" { if !open { return false }; open = false }
        }
        return !open
    }
}
