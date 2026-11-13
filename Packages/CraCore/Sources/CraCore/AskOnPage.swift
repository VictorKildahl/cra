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

    /// The existing deterministic UI fixture model, returning native fields from the fitted source.
    /// It never certifies model quality, and it does not invent punctuation outside that source.
    public static func fixtureDraft(question: String, source: String) -> Draft {
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
        guard let quote = sentences.first(where: { sentence in words.contains { sentence.lowercased().contains($0) } }) ?? sentences.first else {
            return .init(excerpts: [], answer: "I think it is not on the page, so this is just a guess.")
        }
        return .init(excerpts: [quote], answer: quote, keyAnswer: String(quote.split(separator: " ").prefix(4).joined(separator: " ")))
    }

    public struct Turn: Equatable, Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
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
        let quotes = excerpts.map { text -> Quote in
            let candidate = normalized(text)
            return Quote(text: text, state: !candidate.isEmpty && source.contains(candidate) ? .verified : .notFound)
        }
        return Answer(text: text, keyAnswer: draft.keyAnswer, quotes: quotes, isComplete: true)
    }

    /// Only canonical Unicode and whitespace fold. Case and punctuation remain evidence.
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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

/// Ask's preferred card fits the focused page; 450 caps the conversation, not the whole panel.
public enum AskOnPageLayout {
    public static let maximumWidth: CGFloat = 400
    public static let maximumConversationHeight: CGFloat = 450

    public static func frame(preferred: CGSize, page: CGRect, inset: CGFloat) -> CGRect {
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
/// Ask button. Arc's capture on a lavender space shows a mid purple; here it is the space's colour
/// at a readable strength, kept to its hue. A grey space gets Max's blue.
///
/// The card follows macOS, not the space (its panel isn't in the space's shell), so a light space
/// on a dark Mac has a dark card (#408). Both questions are made, the card picks by its own
/// appearance, and each one reads at least 4.5:1 (WCAG AA) on its card: a colour too dark for the
/// dark card is lifted, then washed toward white; one too light for the light card is darkened.
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
        let c = HexColor.components(themeHex) ?? (0.5, 0.5, 0.5)
        var (h, s, _) = Self.hsb(c.r, c.g, c.b)
        var light = (s: max(s, 0.55), v: 0.62), dark = (s: max(s, 0.45), v: 0.92)
        if s < 0.08 {
            // Max's blue: (0.22, 0.24, 1) on light, (0.47, 0.50, 1) on dark.
            (h, s, _) = Self.hsb(0.22, 0.24, 1)
            light = (s, 1)
            dark = (Self.hsb(0.47, 0.50, 1).1, 1)
        }
        let lightCard = Self.card(dark: false), darkCard = Self.card(dark: true)
        questionOnLight = Self.readable(h: h, s: light.s, v: light.v, on: (lightCard, lightCard, lightCard), lighter: false)
        questionOnDark = Self.readable(h: h, s: dark.s, v: dark.v, on: (darkCard, darkCard, darkCard), lighter: true)
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
