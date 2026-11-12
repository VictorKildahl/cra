import Foundation

/// Ask on Page's transient dialogue and citations. Browser ownership and model tasks live in the app.
public enum AskOnPage {
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
        public private(set) var olderMessagesHidden = false

        public init() {}

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

    public enum QuoteState: Equatable, Sendable {
        case verified, notFound, incomplete, malformed
    }

    public enum Part: Equatable, Sendable {
        case text(String)
        case quote(markdown: String, plainText: String, state: QuoteState)
    }

    public struct Answer: Equatable, Sendable {
        public let parts: [Part]
        public let wasTruncated: Bool
        public var hasVerifiedQuote: Bool {
            parts.contains { if case .quote(_, _, .verified) = $0 { return true }; return false }
        }
    }

    /// FoundationModels yields cumulative snapshots: parse the latest bounded text afresh, rather
    /// than appending each snapshot as a delta or maintaining another incremental parser state.
    public static func answer(_ snapshot: String, source: String) -> Answer {
        let bounded = prefix(snapshot, maximumBytes: 65_536)
        let normalizedSource = normalized(source)
        var parts: [Part] = []
        var text: [String] = []
        var quote: [String]?
        var malformed = false

        func flushText() {
            let value = text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { parts.append(.text(value)) }
            text.removeAll(keepingCapacity: true)
        }
        func finishQuote(incomplete: Bool) {
            let markdown = (quote ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let plain = attributed.map { String($0.characters) } ?? markdown
            let search = normalized(plain)
            let state: QuoteState = malformed || search.isEmpty ? .malformed : incomplete ? .incomplete
                : normalizedSource.contains(search) ? .verified : .notFound
            parts.append(.quote(markdown: markdown, plainText: plain, state: state))
            quote = nil
            malformed = false
        }

        for line in bounded.split(separator: "\n", omittingEmptySubsequences: false) {
            let value = String(line)
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag == "<excerpt>" {
                if quote != nil {
                    malformed = true
                    quote?.append(value)
                } else {
                    flushText()
                    quote = []
                }
            } else if tag == "</excerpt>", quote != nil {
                finishQuote(incomplete: false)
            } else if quote != nil {
                if value.contains("<excerpt>") || value.contains("</excerpt>") { malformed = true }
                quote?.append(value)
            } else {
                text.append(value)
            }
        }
        if quote != nil { finishQuote(incomplete: true) }
        flushText()
        return Answer(parts: parts, wasTruncated: bounded != snapshot)
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
