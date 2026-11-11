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
