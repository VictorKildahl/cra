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
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?.replacingOccurrences(of: "&", with: "%26") ?? query
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

    public var id: String {
        switch self {
        case .browseForMe: return "browse-for-me"
        case .engine(let engine): return engine.rawValue
        }
    }

    public var label: String {
        switch self {
        case .browseForMe: return "Browse for Me"
        case .engine(let engine): return engine.label
        }
    }

    /// The menu: Browse for Me only where the device's own model can answer.
    public static func all(browseForMeAvailable: Bool) -> [MobileSearchChoice] {
        (browseForMeAvailable ? [.browseForMe] : []) + MobileSearchEngine.allCases.map { .engine($0) }
    }
}
