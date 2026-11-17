import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Ask on Page's transient dialogue and citations. Browser ownership and model tasks live in the app.
public enum AskOnPage {
    public static let disabledNotification = Notification.Name("CraAskOnPageDisabled")
    public static let profileChangedNotification = Notification.Name("CraAskOnPageProfileChanged")
    public static let unavailableNotification = Notification.Name("CraAskOnPageUnavailable")
    public enum FindPurpose: Equatable, Sendable { case ordinary, quote }

    /// One exact query session. Native identifiers are evidence, not caller-supplied IDs.
    public struct FindRequest: Equatable, Sendable {
        public let id: UUID
        public let query: String
        public let matchCase: Bool
        public let purpose: FindPurpose
    }

    public struct FindState: Equatable, Sendable {
        public private(set) var request: FindRequest?
        public private(set) var count: Int?
        public private(set) var activeMatch = 0
        public private(set) var identifier: Int?
        public private(set) var finalUpdate = false
        private var finalZero = false

        public init() {}

        /// Repeated next/previous searches remain in the same native query session.
        @discardableResult
        public mutating func begin(_ query: String, matchCase: Bool = false, purpose: FindPurpose = .ordinary) -> FindRequest {
            if let request, request.query == query, request.matchCase == matchCase, request.purpose == purpose { return request }
            clear()
            let next = FindRequest(id: UUID(), query: query, matchCase: matchCase, purpose: purpose)
            request = next
            return next
        }

        public mutating func clear() { self = Self() }

        @discardableResult
        public mutating func accept(_ generation: UUID, quote: Bool, identifier: Int, count: Int, activeMatch: Int, finalUpdate: Bool) -> Bool {
            guard let request, request.id == generation, (request.purpose == .quote) == quote else { return false }
            self.identifier = identifier
            self.finalUpdate = finalUpdate
            if count >= 0 { self.count = count }
            if activeMatch >= 0 { self.activeMatch = activeMatch }
            // A final unknown count cannot turn an earlier partial zero into proof.
            finalZero = finalUpdate && count == 0
            return true
        }

        public func canAsk(query: String, enabled: Bool, forward: Bool) -> Bool {
            enabled && forward && finalZero && request?.purpose == .ordinary && request?.query == query
                && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The test model's answer (CRA_TIDY_FAKE_MODEL=1), returning native fields from the fitted source.
    /// It never certifies model quality. Asked for a summary, it lists the page's sentences, as long as
    /// the real model's summaries run; asked to make something up, it quotes a sentence the page
    /// doesn't have; asked to repeat the page, its first answer (`echoed` 0) is the request copied
    /// back, as the real model's sometimes is.
    public static func fixtureDraft(question: String, source: String, echoed: Int = 0) -> Draft {
        let asked = question.lowercased()
        if asked.contains("repeat the page"), echoed == 0 {
            return .init(excerpts: [], answer: "<url>https://example.test/</url>\n<current-date>today</current-date>\n" + String(source.prefix(200)))
        }
        if asked.contains("make up") || asked.contains("made-up") {
            return .init(excerpts: [fixtureMadeUpQuote], answer: "A guess.", keyAnswer: "guess")
        }
        let words = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 3 }.map(String.init))
        var sentences: [String] = [], sentence = ""
        for character in source {
            sentence.append(character)
            if ".!?\n".contains(character) {
                let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 12 { sentences.append(text) }
                sentence = ""
            }
        }
        let tail = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 12 { sentences.append(tail) }
        if Form(question: question) == .summary {
            let points = sentences.prefix(fixtureSummaryPoints).map { "• " + $0 }
            return .init(excerpts: [], answer: "Here are the key points of the page:\n" + points.joined(separator: "\n"))
        }
        guard let quote = sentences.first(where: { sentence in words.contains { sentence.lowercased().contains($0) } }) ?? sentences.first else {
            return .init(excerpts: [], answer: "I think it is not on the page, so this is just a guess.")
        }
        return .init(excerpts: [quote], answer: quote, keyAnswer: String(quote.split(separator: " ").prefix(4).joined(separator: " ")))
    }

    public static let fixtureMadeUpQuote = "The moon is made of green cheese, the article says."
    /// How many points the test model's summary has.
    public static let fixtureSummaryPoints = 28

    public struct Turn: Equatable, Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// What an answer is made of. Arc's prompt answers "summary" with a brief summary and no quote, and a
    /// question with a quote and a short answer. The on-device model doesn't tell the two apart: asked to
    /// list a release's features, it copied one paragraph as the quote and again as the answer (#417).
    /// So a summary or a list gets no quotes unless the question asks for them.
    public enum Form: Equatable, Sendable {
        /// Page sentences as quotes, then a short answer: Arc's answer to a question.
        case quoted
        /// A short list of points in the model's own words, without quotes.
        case summary

        public init(question: String) {
            let asked = question.lowercased()
            let words = asked.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            func has(_ phrase: String) -> Bool {
                let phrase = phrase.split(separator: " ").map(String.init)
                return words.indices.contains { start in
                    start + phrase.count <= words.count && Array(words[start..<start + phrase.count]) == phrase
                }
            }
            if Self.quoteWords.contains(where: has) || asked.contains("where does it say") {
                self = .quoted
            } else if Self.summaryWords.contains(where: has) || asked.contains("tl;dr") || words.first == "list" {
                self = .summary
            } else {
                self = .quoted
            }
        }

        /// A summary or list that names one of these still quotes the page: the reader asked for it.
        static let quoteWords = ["quote", "quotes", "quoted", "quoting", "cite", "citing", "citation", "citations",
                                 "excerpt", "excerpts", "references", "sources", "evidence"]
        /// Asking for a summary or a list. "List" alone ("is it on the list?") only counts at the start.
        static let summaryWords = ["summary", "summaries", "summarize", "summarise", "summarizing", "summarising", "sum up",
                                   "tldr", "bullet", "bullets", "bulleted", "key points", "main points", "takeaways",
                                   "highlights", "overview", "outline", "list out", "list all", "list the", "list every",
                                   "a list"]
    }

    /// Only completed pairs enter history; eviction never leaves an answer without its question.
    public struct History: Equatable, Sendable {
        public static let maximumTurns = 12
        public static let maximumBytes = 65_536
        public private(set) var turns: [Turn] = []
        public private(set) var olderMessagesHidden: Bool

        public init(olderMessagesHidden: Bool = false) { self.olderMessagesHidden = olderMessagesHidden }

        public mutating func append(_ turn: Turn) {
            turns.append(turn)
            var bytes = turns.reduce(0) { $0 + $1.question.utf8.count + $1.answer.utf8.count }
            while turns.count > Self.maximumTurns || bytes > Self.maximumBytes {
                let removed = turns.removeFirst()
                bytes -= removed.question.utf8.count + removed.answer.utf8.count
                olderMessagesHidden = true
            }
        }
    }

    public struct Draft: Equatable, Sendable {
        public var excerpts: [String]?
        public var answer: String?
        public var keyAnswer: String?

        public init(excerpts: [String]? = nil, answer: String? = nil, keyAnswer: String? = nil) {
            self.excerpts = excerpts; self.answer = answer; self.keyAnswer = keyAnswer
        }
    }

    public enum QuoteState: Equatable, Sendable { case unverified, verified, notFound }
    public struct Quote: Equatable, Sendable {
        public let text: String
        public let state: QuoteState
        /// What Find looks for: the page's own characters for a verified quote (its en dash where the
        /// answer typed a hyphen), the answer's text otherwise.
        public let findText: String
        public init(text: String, state: QuoteState, findText: String? = nil) {
            self.text = text
            self.state = state
            self.findText = findText ?? text
        }
    }
    public struct Answer: Equatable, Sendable {
        public let text: String
        public let keyAnswer: String?
        public let quotes: [Quote]
        public let isComplete: Bool
        /// Text presence in the transmitted source, not semantic support for the answer.
        public var hasVerifiedQuote: Bool { quotes.contains { $0.state == .verified } }
        public var emphasisRange: NSRange? {
            guard let keyAnswer, !keyAnswer.isEmpty, let range = text.range(of: keyAnswer, options: .literal) else { return nil }
            return NSRange(range, in: text)
        }
        /// Only internal history context; native UI consumes the fields directly.
        public var historyText: String { (quotes.map(\.text) + [text]).joined(separator: "\n") }
    }

    /// Partial generated fields replace earlier fields. No provisional quotation is actionable.
    public static func partialAnswer(_ draft: Draft) -> Answer {
        var remaining = 65_536
        func take(_ text: String) -> String {
            let result = prefix(text, maximumBytes: remaining)
            remaining -= result.utf8.count
            return result
        }
        let text = take(draft.answer ?? "")
        let key = draft.keyAnswer.map(take)
        let quotes = (draft.excerpts ?? []).prefix(4).map { Quote(text: take($0), state: .unverified) }
        return Answer(text: text, keyAnswer: key, quotes: quotes, isComplete: false)
    }

    /// Required-field completeness is separate from citation validity and optional emphasis:
    /// complete empty citation arrays remain legitimate conversation turns.
    public static func completeAnswer(_ draft: Draft, source: String) -> Answer? {
        guard let excerpts = draft.excerpts, let text = draft.answer,
              excerpts.count <= 4, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              excerpts.reduce(text.utf8.count + (draft.keyAnswer?.utf8.count ?? 0), { $0 + $1.utf8.count }) <= 65_536 else { return nil }
        let source = normalized(source)
        let foldedSource = String(source.map(folded))
        let quotes = excerpts.map { text -> Quote in
            let candidate = String(normalized(text).map(folded))
            guard !candidate.isEmpty, let range = foldedSource.range(of: candidate, options: .literal) else {
                return Quote(text: text, state: .notFound)
            }
            // Folding swaps one character for one, so the span sits at the same characters in the source.
            let start = source.index(source.startIndex, offsetBy: foldedSource.distance(from: foldedSource.startIndex, to: range.lowerBound))
            let end = source.index(start, offsetBy: foldedSource.distance(from: range.lowerBound, to: range.upperBound))
            return Quote(text: text, state: .verified, findText: String(source[start..<end]))
        }
        return Answer(text: text, keyAnswer: draft.keyAnswer, quotes: quotes, isComplete: true)
    }

    /// A summary's points as the card shows them, each on a line of its own after "• ". The model
    /// writes them as a list of strings: asked for one point per line in a single answer, it wrote them
    /// as one paragraph every time and ran on past its room on long pages (#417). A point it already
    /// made is left out: with three fixes on the page it filled eight places by going round again.
    public static func listed(points: [String]) -> String {
        var seen = Set<String>()
        return points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("•") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty && seen.insert(normalized($0).lowercased()).inserted }
            .map { "• " + $0 }.joined(separator: "\n")
    }

    /// A streaming answer's lines, each drawn on its own so only the last one is laid out again. An
    /// empty line keeps its height as a space.
    public static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.isEmpty ? " " : $0 }
    }

    /// Only canonical Unicode and whitespace fold. Case and punctuation remain evidence.
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Typographic forms of the same mark: the model types a hyphen and straight quotes where pages print
    /// dashes, minus signs, curly quotes and primes. One character for one; other punctuation stays evidence.
    static func folded(_ c: Character) -> Character {
        switch c {
        case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}", "\u{FE58}", "\u{FE63}", "\u{FF0D}": return "-"
        case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}", "\u{FF07}": return "'"
        case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}", "\u{FF02}": return "\""
        default: return c
        }
    }

    /// A byte limit that never cuts a composed character, shared by context and response bounds.
    static func prefix(_ text: String, maximumBytes: Int) -> String {
        var bytes = 0
        var end = text.startIndex
        for character in text {
            let size = character.utf8.count
            if bytes + size > maximumBytes { break }
            bytes += size
            end = text.index(after: end)
        }
        return String(text[..<end])
    }
}


/// Arc 1.109's page gate and the existing combined Find or Ask presentation.
/// An eligible URL/type still requires a genuine current HTML snapshot before generation.
public enum AskOnPagePolicy {
    public enum ReturnKey: Equatable, Sendable { case nextMatch, ask }

    public enum DocumentKind: Equatable, Sendable { case unknown, html, pdf, image, movie, other }

    public static func supportsURL(_ page: URL?) -> Bool {
        guard let page, let scheme = page.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return page.host?.lowercased() != "search.arc.net"
    }

    public static func canAsk(page: URL?, incognito: Bool, documentKind: DocumentKind) -> Bool {
        supportsURL(page) && !incognito && ![.pdf, .image, .movie].contains(documentKind)
    }

    public static func placeholder(canAsk: Bool, inConversation: Bool) -> String {
        if !canAsk { return "Find in page…" }
        return inConversation ? "Ask a question…" : "Find or ask…"
    }

    /// Display counts cannot prove ownership. Only the manager's correlated final zero may ask.
    public static func returnKey(query: String, finalZero: Bool, inConversation: Bool,
                                 canAsk: Bool, forward: Bool) -> ReturnKey? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard forward, canAsk else { return .nextMatch }
        return inConversation || finalZero ? .ask : .nextMatch
    }

    public static func showsAskButton(query: String, canAsk: Bool) -> Bool {
        canAsk && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// How often a streaming answer reaches the card: at most ten times a second. Each snapshot redrew
/// the whole conversation; a real summary from the on-device model cost 234 frames over 16 ms, 5–9
/// paced (#417).
public struct AskOnPageStreamPacing: Equatable, Sendable {
    public static let interval: TimeInterval = 0.1
    private var lastShown: TimeInterval?

    public init() {}

    /// How long to wait before showing a snapshot that arrived at `now`: 0 shows it now.
    public func delay(at now: TimeInterval) -> TimeInterval {
        guard let lastShown else { return 0 }
        return max(0, lastShown + Self.interval - now)
    }

    public mutating func shown(at now: TimeInterval) { lastShown = now }
}

/// Ask's preferred card fits the focused page; 450 caps the conversation, not the whole panel.
public enum AskOnPageLayout {
    public static let maximumWidth: CGFloat = 400
    public static let maximumConversationHeight: CGFloat = 450

    public static func frame(preferred: CGSize, page: CGRect, inset: CGFloat, toolbarOverPage: CGFloat = 0) -> CGRect {
        // The floating toolbar covers the page's top. Constrain the whole card below it,
        // including a short page's conversation, rather than shifting a full-height card out.
        var page = page
        page.size.height = max(0, page.height - max(0, toolbarOverPage))
        let dx = min(max(0, inset), max(0, page.width) / 2)
        let dy = min(max(0, inset), max(0, page.height) / 2)
        let width = min(maximumWidth, max(0, preferred.width), max(0, page.width - 2 * dx))
        let height = min(max(0, preferred.height), max(0, page.height - 2 * dy))
        return CGRect(x: page.maxX - dx - width, y: page.maxY - dy - height, width: width, height: height)
    }

    public static func conversationHeight(content: CGFloat, input: CGFloat, available: CGFloat) -> CGFloat {
        min(maximumConversationHeight, max(0, content), max(0, available - input))
    }
}

/// The card's theme colour (Arc's WindowTheme palette, read at run time there): the question, the
/// Ask button. Arc's capture on a lavender space shows a mid purple; here it is the space's own colour
/// with only its lightness moved (#490): a dark one is first lifted to mid strength (luminance 0.306,
/// Arc's midTone floor), then each card's question goes only as far as reading needs. Hue and saturation
/// stay, so a sage space asks in sage and a vivid one is never bolder than itself. The colourless
/// default asks in Arc's default blue (its midTone). A grey space gets Max's blue.
///
/// The card follows macOS, not the space (its panel isn't in the space's shell), so a light space
/// on a dark Mac has a dark card (#408). Both questions are made, the card picks by its own
/// appearance, and each one reads at least 4.5:1 (WCAG AA) on its card: a colour too dark for the
/// dark card is lightened, one too light for the light card is darkened, both keeping hue and saturation.
/// The Ask button carries white text, so it takes the light card's question in both appearances.
public struct AskOnPageTone {
    public typealias RGB = (r: Double, g: Double, b: Double)

    public static let minimumContrast = 4.5
    /// The card's grey in each appearance (it is 96–97 % opaque over the page).
    public static func card(dark: Bool) -> Double { dark ? 0.16 : 0.985 }

    public let questionOnLight: RGB
    public let questionOnDark: RGB
    /// The Ask button's fill, under white text.
    public var button: RGB { questionOnLight }

    public func question(dark: Bool) -> RGB { dark ? questionOnDark : questionOnLight }

    public init(themeHex: String) {
        let lightCard = Self.card(dark: false), darkCard = Self.card(dark: true)
        let colourless = ["#010220", "#01021F", "#C8CAFF"].contains(themeHex.uppercased())
        let own = HexColor.components(themeHex) ?? (0.5, 0.5, 0.5)
        // Arc's stored default palette's midTone, (131.1, 137.2, 258.7) (SpaceTheme.midTone of these colours).
        let source = colourless ? (r: 131.1 / 255, g: 137.2 / 255, b: 258.7 / 255) : own
        let c = (r: min(1, max(0, source.r)), g: min(1, max(0, source.g)), b: min(1, max(0, source.b)))
        if Self.hsb(c.r, c.g, c.b).1 < 0.08 {
            // Max's blue: (0.22, 0.24, 1) on light, (0.47, 0.50, 1) on dark.
            let (h, s, _) = Self.hsb(0.22, 0.24, 1)
            questionOnLight = Self.readable(h: h, s: s, v: 1, on: (lightCard, lightCard, lightCard), lighter: false)
            questionOnDark = Self.readable(h: h, s: Self.hsb(0.47, 0.50, 1).1, v: 1, on: (darkCard, darkCard, darkCard), lighter: true)
            return
        }
        let base = Self.lifted(c, toLuminance: 0.306)
        questionOnLight = Self.readable(base, on: (lightCard, lightCard, lightCard), lighter: false)
        questionOnDark = Self.readable(base, on: (darkCard, darkCard, darkCard), lighter: true)
    }

    /// `c` with its HSL lightness raised until its luminance is at least `floor`; hue and saturation kept.
    static func lifted(_ c: RGB, toLuminance floor: Double) -> RGB {
        var (h, s, l) = hsl(c)
        while luminance(at(h, s, l)) < floor, l < 1 { l = min(1, l + 0.005) }
        return at(h, s, l)
    }

    static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn, l = (mx + mn) / 2
        return (hsb(c.r, c.g, c.b).0, d < 0.00001 ? 0 : (l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)), l)
    }

    static func at(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        let chroma = (1 - abs(2 * l - 1)) * s, m = l - chroma / 2, o = rgb(h: h, s: 1, v: 1)
        return (m + o.r * chroma, m + o.g * chroma, m + o.b * chroma)
    }

    /// `c` with its HSL lightness stepped until it reads on bg, hue and saturation kept: lighter toward
    /// white, darker toward black (both ends read on the card's greys). A colour that reads is kept.
    static func readable(_ c: RGB, on bg: RGB, lighter: Bool) -> RGB {
        var (h, s, l) = hsl(c)
        if s == 0 { h = 0 }
        while contrast(at(h, s, l), bg) < minimumContrast {
            if lighter { guard l < 1 else { break }; l = min(1, l + 0.005) } else { guard l > 0 else { break }; l = max(0, l - 0.005) }
        }
        return at(h, s, l)
    }

    /// WCAG 2 contrast ratio of two sRGB colours (1 to 21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// The hue at s, v, stepped until it reads on bg: lighter raises v, then lowers s (toward
    /// white); darker lowers v (toward black). Both ends always read on the card's greys.
    static func readable(h: Double, s: Double, v: Double, on bg: RGB, lighter: Bool) -> RGB {
        var s = s, v = v
        while true {
            let c = rgb(h: h, s: s, v: v)
            if contrast(c, bg) >= minimumContrast { return c }
            if lighter {
                if v < 1 { v = min(1, v + 0.01) } else if s > 0 { s = max(0, s - 0.01) } else { return c }
            } else {
                if v > 0 { v = max(0, v - 0.01) } else { return c }
            }
        }
    }

    static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func rgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
