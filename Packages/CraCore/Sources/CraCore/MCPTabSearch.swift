import Foundation

/// Matching rules for the read-only MCP search over open tabs.
public enum MCPTabSearch {
    /// Every query word must appear in the title or URL. Optional sidebar filters match exactly,
    /// ignoring case, diacritics and width so agents can use visible names naturally.
    public static func matches(query: String, title: String, url: String,
                                space: String?, folder: String?, section: String?,
                                spaceFilter: String? = nil, folderFilter: String? = nil,
                                sectionFilter: String? = nil) -> Bool {
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }

        let searchable = normalized(title + " " + url)
        guard words.allSatisfy({ searchable.contains($0) }) else { return false }
        return matches(spaceFilter, value: space)
            && matches(folderFilter, value: folder)
            && matches(sectionFilter, value: section)
    }

    private static func matches(_ filter: String?, value: String?) -> Bool {
        guard let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return normalized(filter.trimmingCharacters(in: .whitespacesAndNewlines)) == normalized(value ?? "")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
