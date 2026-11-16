import Foundation

/// The iPhone app's search engines: Arc Search's list, in its order.
public enum MobileSearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, bing, duckduckgo, ecosia, perplexity, kagi

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .ecosia: return "Ecosia"
        case .perplexity: return "Perplexity"
        case .kagi: return "Kagi"
        }
    }

    /// The engine the Mac app knows, where it knows it.
    private var shared: SearchEngine? {
        switch self {
        case .google: return .google
        case .bing: return .bing
        case .duckduckgo: return .duckduckgo
        case .kagi: return .kagi
        case .ecosia, .perplexity: return nil
        }
    }

    private static func encoded(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?.replacingOccurrences(of: "&", with: "%26").replacingOccurrences(of: "+", with: "%2B") ?? query
    }

    public func searchURL(_ query: String) -> String {
        if let shared { return shared.searchURL(query) }
        switch self {
        case .ecosia: return "https://www.ecosia.org/search?q=\(Self.encoded(query))"
        default: return "https://www.perplexity.ai/search?q=\(Self.encoded(query))"
        }
    }

    /// The engine's OpenSearch suggest endpoint. Perplexity has none.
    public func suggestURL(_ query: String) -> URL? {
        if let shared { return shared.suggestURL(query) }
        guard self == .ecosia, let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "https://ac.ecosia.org/autocomplete?q=\(q)&type=list")
    }
}

/// A choice in App Settings ▸ Search Engine: Arc Search's v1.2 menu lists "Browse for Me" first,
/// then the engines.
public enum MobileSearchChoice: Hashable, Identifiable {
    case browseForMe
    case engine(MobileSearchEngine)
    /// The address the user gave, `%s` for the query (Arc Search 1.16 "custom search engines").
    case custom

    public var id: String {
        switch self {
        case .browseForMe: return "browse-for-me"
        case .engine(let engine): return engine.rawValue
        case .custom: return "custom"
        }
    }

    public var label: String {
        switch self {
        case .browseForMe: return "Browse for Me"
        case .engine(let engine): return engine.label
        case .custom: return "Custom"
        }
    }

    /// The menu: Browse for Me only where the device's own model can answer.
    public static func all(browseForMeAvailable: Bool) -> [MobileSearchChoice] {
        (browseForMeAvailable ? [.browseForMe] : []) + MobileSearchEngine.allCases.map { .engine($0) } + [.custom]
    }
}

/// Where searches go: one of the engines, or a custom address with `%s` for the query.
public struct MobileSearch: Equatable {
    public var engine: MobileSearchEngine
    /// A custom engine's address, `%s` where the query goes; nil uses `engine`.
    public var customTemplate: String?

    public init(_ engine: MobileSearchEngine, customTemplate: String? = nil) {
        self.engine = engine
        self.customTemplate = customTemplate.flatMap { Self.isValidTemplate($0) ? $0 : nil }
    }

    public static let google = MobileSearch(.google)
    public static let bing = MobileSearch(.bing)
    public static let duckduckgo = MobileSearch(.duckduckgo)
    public static let ecosia = MobileSearch(.ecosia)
    public static let perplexity = MobileSearch(.perplexity)
    public static let kagi = MobileSearch(.kagi)

    /// A custom engine's address must be https with exactly one `%s`.
    public static func isValidTemplate(_ template: String) -> Bool {
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard trimmed.components(separatedBy: "%s").count == 2,
              let url = URL(string: trimmed.replacingOccurrences(of: "%s", with: "q")),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    /// The name on the switch and in the menu: the custom engine is named by its site.
    public var label: String {
        guard let customTemplate else { return engine.label }
        let host = URL(string: customTemplate.replacingOccurrences(of: "%s", with: "q"))?.host ?? "Custom"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public func searchURL(_ query: String) -> String {
        guard let customTemplate else { return engine.searchURL(query) }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? query
        return customTemplate.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%s", with: encoded)
    }

    /// Suggestions come from the built-in engines only.
    public func suggestURL(_ query: String) -> URL? {
        customTemplate == nil ? engine.suggestURL(query) : nil
    }

    /// The query on this search's results page, or nil.
    public func query(fromResultsURL address: String) -> String? {
        guard let customTemplate else { return engine.query(fromResultsURL: address) }
        let parts = customTemplate.trimmingCharacters(in: .whitespaces).components(separatedBy: "%s")
        guard parts.count == 2, address.hasPrefix(parts[0]) else { return nil }
        var rest = String(address.dropFirst(parts[0].count))
        if !parts[1].isEmpty {
            guard let end = rest.range(of: parts[1]) else { return nil }
            rest = String(rest[..<end.lowerBound])
        } else if let amp = rest.firstIndex(where: { $0 == "&" || $0 == "#" }) {
            rest = String(rest[..<amp])
        }
        let query = rest.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?.trimmingCharacters(in: .whitespaces)
        return query?.isEmpty == false ? query : nil
    }
}
