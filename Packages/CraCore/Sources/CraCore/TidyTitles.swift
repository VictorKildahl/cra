import Foundation

/// Arc Max's Tidy Tab Titles (renamePinnedTabs): the prompt and how the answer becomes a name.
/// Arc 1.173.1 builds the prompt in WindowState+AIRenameTabs (0x1000c00b4, text at 0x1039bca00),
/// keeps the rewrite only when it isn't longer than the filtered title (0x1000bf6f0) and takes the
/// widest that fits the row's title, or the narrowest when none fits (0x1000bff88). Measuring the
/// text and calling the on-device model belong to the app.
public enum TidyTitles {
    /// A local resource bound, not a word limit on Arc's filtered title.
    static let maximumLength = 512
    public static let responseTokenLimit = 384

    public struct Answer {
        public var filtered: String
        public var rewritten: String

        public init(filtered: String, rewritten: String) {
            self.filtered = filtered
            self.rewritten = rewritten
        }
    }

    /// Arc's prompt word for word, with the title and site moved out to the request. On the Mac's
    /// model it names tabs as well as Cra's earlier prompt with examples and a reworded one did
    /// (11–12 of 18 sample titles each, none of them in a prompt; scripts/test-tidy-titles-model.sh
    /// --real), so Arc's own text stays.
    public static let instructions = """
    You are a perfect editor, summarizer and translator.
    I am bookmarking a tab in my browser.
    - Remove the name of the site, if it's not the only thing there.
    - Remove other SEO cruft
    - Don't make the title too general. As specific as possible without going over the word count.
    - If the page is about a proper noun (personal site, restaurant homepage, brand homepage), the new \
    title should always include the proper noun along with context. For example, "Individualized Eng \
    Expectations - Anna Delvey" would translate to "Anna's Eng Expectations", and "Arc by the Browser \
    Company: Monetization Strategy" would translate to "Arc Monetization".
    - Remove words that describe the 'kind of page' (video, recipe, guide, etc)
    - Err on the side of keeping the subject, main verb, and direct object. Remove other parts of speech.
    Return a response using JSON, according to this schema:
        filtered: string // The title translated and filtered to remove the cruft. No word limit.
        rewritten: string // The title rewritten in 1-3 words
    """

    /// Arc ends its prompt with the user's language (Locale.preferredLanguages, named in English).
    public static func instructions(language: String) -> String {
        instructions + "\nWrite responses (but not JSON keys) in \(responseLanguage(language))."
    }

    /// The page as Arc gives it: the title in backticks and its site. The instructions stay apart
    /// from the page's text, which is one line with no backticks, so a title can't add a line or
    /// close the quote. Arc gives the whole URL; Cra gives the host, which named tabs as well on the
    /// Mac's model and keeps paths and query strings (ids, tokens) out of the request.
    public static func prompt(title: String, url: String, compact: Bool = false) -> String {
        let line = title.unicodeScalars.map { scalar -> String in
            if scalar == "`" { return "'" }
            return scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar) ? " " : String(scalar)
        }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let site = clip(host(url), 253, bytes: 1_024)
        return "The title is `\(clip(line, compact ? 100 : 200, bytes: compact ? 400 : 800))` (site: \(site))"
    }

    /// Reserve output and a small transcript margin; field bounds alone are not a token guarantee.
    public static func fitsContext(inputTokens: Int, contextSize: Int) -> Bool {
        let reserved = responseTokenLimit + 128
        return inputTokens >= 0 && contextSize >= reserved && inputTokens <= contextSize - reserved
    }

    public static func shouldRetry(attempt: Int, contextOverflow: Bool, cancelled: Bool) -> Bool {
        attempt == 0 && contextOverflow && !cancelled
    }

    /// Normalize display text without discarding informative long or translated alternatives.
    public static func clean(_ answer: String) -> String? {
        let whitespace = CharacterSet.whitespacesAndNewlines
        // Foundation's controlCharacters also includes format scalars such as valid ZWJ/ZWNJ.
        guard !answer.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !whitespace.contains($0) }) else { return nil }
        let s = answer.trimmingCharacters(in: whitespace.union(CharacterSet(charactersIn: "\"'“”‘’«»`")))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return !s.isEmpty && s.count <= maximumLength ? s : nil
    }

    /// Arc reduces the raw pair before filtering; display cleaning must not change that decision.
    public static func candidates(_ answer: Answer) -> [String] {
        let raw = answer.filtered.count < answer.rewritten.count ? [answer.filtered] : [answer.filtered, answer.rewritten]
        return raw.compactMap(clean)
    }

    /// Largest measured candidate that fits, or the smallest when none fit. Ties keep input order.
    public static func select(_ candidates: [(title: String, width: Double)], availableWidth: Double, shown: String) -> String? {
        let available = availableWidth.isFinite ? max(0, availableWidth) : 0
        var fitting: (title: String, width: Double)?
        var smallest: (title: String, width: Double)?
        for candidate in candidates where candidate.width.isFinite && candidate.width > 0 {
            if smallest == nil || candidate.width < smallest!.width { smallest = candidate }
            if candidate.width <= available && (fitting == nil || candidate.width > fitting!.width) { fitting = candidate }
        }
        guard let title = (fitting ?? smallest)?.title,
              title.lowercased() != (clean(shown) ?? shown).lowercased() else { return nil }
        return title
    }

    /// Library's Spaces cards reuse tab IDs and window IDs but do not represent the sidebar.
    public static func usesSidebarLayout(windowID: UUID, originWindowID: UUID, hasWindow: Bool, showsNewTab: Bool) -> Bool {
        windowID == originWindowID && hasWindow && showsNewTab
    }

    /// A pinned name describes its home, so ordinary navigation alone does not invalidate it.
    public static func canApply(enabled: Bool, pinned: Bool, customTitle: String?,
                                shown: String?, originalShown: String, homeURL: String?, originalHomeURL: String) -> Bool {
        enabled && pinned && customTitle == nil && shown == originalShown && homeURL == originalHomeURL
    }

    static func host(_ url: String) -> String {
        guard let h = URL(string: url)?.host?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func responseLanguage(_ language: String) -> String {
        let bounded = clip(language.split(whereSeparator: \.isWhitespace).joined(separator: " "), 64, bytes: 256)
        return bounded.isEmpty ? "English" : bounded
    }

    /// Both limits matter: one composed grapheme can contain arbitrarily many Unicode scalars.
    static func clip(_ s: String, _ characters: Int, bytes: Int) -> String {
        var result = ""
        var remaining = bytes
        for character in s.prefix(characters) {
            let length = character.utf8.count
            guard length <= remaining else { break }
            result.append(character)
            remaining -= length
        }
        return result
    }
}
