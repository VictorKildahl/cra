import Foundation

/// Arc Search's page summary ("Summarize" in the page menu, or a pinch): a paragraph, then a few
/// titled sections. In Cra the device's own model writes it; these are its instructions, the
/// prompt, and the shape of the answer.
public enum MobileSummary {
    public struct Section: Equatable, Sendable, Identifiable {
        public var title: String
        public var body: String
        /// An SF Symbol name the model picked for the section's round icon, when it picked one.
        public var symbol: String?
        public var id: String { title }

        public init(title: String, body: String, symbol: String? = nil) {
            self.title = title
            self.body = body
            self.symbol = symbol
        }
    }

    public struct Answer: Equatable, Sendable {
        public var overview: String
        public var sections: [Section]

        public init(overview: String, sections: [Section]) {
            self.overview = overview
            self.sections = sections
        }

        /// Trimmed, without empty sections; nil when the model said nothing usable.
        public var cleaned: Answer? {
            let overview = overview.trimmingCharacters(in: .whitespacesAndNewlines)
            let sections = sections.compactMap { section -> Section? in
                let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
                let symbol = section.symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty || body.isEmpty ? nil : Section(title: title, body: body, symbol: symbol?.isEmpty == false ? symbol : nil)
            }
            return overview.isEmpty && sections.isEmpty ? nil : Answer(overview: overview, sections: Array(sections.prefix(maxSections)))
        }
    }

    public static let maxSections = 5
    /// The on-device model reads 4,096 tokens in all: about 6,000 characters of page leave room
    /// for the instructions and the answer.
    public static let maxTextLength = 6_000

    public static let instructions = """
    You summarize a web page for someone who has not read it. Write one short paragraph that says what the page is about, \
    then three to five sections, each with a short title and two or three sentences. Stay with what the page says. \
    Keep the writer's point of view. Do not mention that you are summarizing.
    """

    /// The page as handed to the model: its title, then its text cut at a sentence where it can be.
    public static func prompt(title: String, text: String, language: String) -> String {
        "Answer in \(language).\n\nWEB PAGE:\n<webpage>\nTitle: \(title)\n\(clipped(text))\n</webpage>"
    }

    /// `text` without runs of blank space, cut to `maxTextLength` at the last sentence end in reach.
    public static func clipped(_ text: String, limit: Int = maxTextLength) -> String {
        let tidy = text.split(whereSeparator: \.isNewline).map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        guard tidy.count > limit else { return tidy }
        let cut = String(tidy.prefix(limit))
        if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > limit / 2 {
            return String(cut[...end])
        }
        return cut
    }

    /// Whether a page has enough text to be worth summarizing.
    public static func canSummarize(text: String) -> Bool {
        clipped(text).count >= 200
    }

    /// The footer under every summary.
    public static let credit = "Summarized for you by Cra"

    /// A stand-in answer for tests, built from the page's own first sentences.
    public static func fakeAnswer(title: String, text: String) -> Answer {
        let sentences = clipped(text).split(whereSeparator: { ".!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let overview = sentences.first.map { $0 + "." } ?? title
        let sections = sentences.dropFirst().prefix(3).enumerated().map { Section(title: "Point \($0.offset + 1)", body: $0.element + ".") }
        return Answer(overview: overview, sections: sections)
    }
}
