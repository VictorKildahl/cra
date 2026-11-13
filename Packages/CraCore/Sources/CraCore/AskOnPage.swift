import Foundation

/// Ask on Page's transient dialogue and citations. Browser ownership and model tasks live in the app.
public enum AskOnPage {
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
