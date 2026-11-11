import Foundation

/// The rows under the iPhone app's search field: what was typed first, then the search engine's
/// completions, four in all (Arc Search's count).
public enum MobileSuggestions {
    public struct Row: Equatable, Identifiable {
        public enum Kind: Equatable {
            /// Searches the default engine for `text`.
            case search
            /// Opens `text` as an address.
            case address
        }

        public var kind: Kind
        public var text: String
        /// How many leading characters of `text` the user typed. Arc Search draws them grey in a
        /// completion and leaves the row for the typed text itself all black.
        public var typedPrefixLength: Int

        public var id: String { "\(kind)|\(text)" }

        public init(kind: Kind, text: String, typedPrefixLength: Int = 0) {
            self.kind = kind
            self.text = text
            self.typedPrefixLength = typedPrefixLength
        }
    }

    /// The rows for `typed` and the engine's `completions`: nothing for an empty field, the typed
    /// text first, then completions that differ from it and from each other.
    public static func rows(typed: String, completions: [String], limit: Int = MobileSearchSheet.visibleRows) -> [Row] {
        let query = typed.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var rows = [Row(kind: TypedURL.looksLikeURL(query) ? .address : .search, text: query)]
        var seen: Set<String> = [query.lowercased()]
        for completion in completions {
            guard rows.count < limit else { break }
            let text = completion.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            let typedLength = text.lowercased().hasPrefix(query.lowercased()) ? query.count : 0
            rows.append(Row(kind: .search, text: text, typedPrefixLength: typedLength))
        }
        return rows
    }

    /// Where a row goes: the address itself, or the engine's results for the text.
    public static func destination(for row: Row, engine: SearchEngine) -> String {
        destination(forTyped: row.text, engine: engine, kind: row.kind)
    }

    /// Where the keyboard's Go key sends what was typed.
    public static func destination(forTyped typed: String, engine: SearchEngine, kind: Row.Kind? = nil) -> String {
        let query = typed.trimmingCharacters(in: .whitespaces)
        let isAddress = kind.map { $0 == .address } ?? TypedURL.looksLikeURL(query)
        return isAddress ? TypedURL.fromInput(query) : engine.searchURL(query)
    }

    /// The completions in an OpenSearch suggest answer, `["query", ["one", "two", …], …]`, which
    /// Google, DuckDuckGo (`type=list`), Bing and Kagi all send. Google's `client=chrome` answer
    /// may open with `)]}'` and marks site suggestions NAVIGATION; those are left out, since the
    /// rows here are searches.
    public static func completions(fromOpenSearch data: Data) -> [String] {
        var body = data
        if let text = String(data: data, encoding: .utf8), text.hasPrefix(")]}'"),
           let stripped = text.dropFirst(4).data(using: .utf8) {
            body = stripped
        }
        guard let answer = try? JSONSerialization.jsonObject(with: body) as? [Any], answer.count > 1,
              let items = answer[1] as? [Any] else { return [] }
        let types = (answer.count > 4 ? answer[4] as? [String: Any] : nil)?["google:suggesttype"] as? [String] ?? []
        return items.enumerated().compactMap { index, item in
            guard let text = item as? String else { return nil }
            if index < types.count, types[index] == "NAVIGATION" { return nil }
            return text
        }
    }
}
