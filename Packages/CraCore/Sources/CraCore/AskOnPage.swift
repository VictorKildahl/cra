import Foundation

/// Arc Max's Ask on Page (`askOnPageEnabled`, Arc's FindInPage + AskInPage modules), on the Mac's own
/// Apple Intelligence model instead of Arc's server.
///
/// Arc's settings text: "Press Command + F on any page to ask a question and let Max answer it for you
/// in seconds." It is Arc's find bar as a card: ⌘F opens one field, "Find or ask…". Typing finds on the
/// page as before (count, previous, next); the Ask button sends the text as a question about the page.
/// The answer quotes the page between `<excerpt>` tags; each quote gets "Find on Page", which runs the
/// page's own find on it. Once a conversation started the field reads "Ask a question…" and only asks.
/// Read from Arc 1.173.1's binary (docs/arc-reverse-engineering.md, "Ask on Page").
public enum AskOnPagePolicy {
    /// What Return does in the field. Arc's binding wasn't readable; Cra finds while the text is on
    /// the page and asks once it isn't (a question rarely is), and always asks in a conversation.
    public enum ReturnKey: Equatable, Sendable {
        case nextMatch, ask
    }

    /// Pages the card can answer about (Arc's `isValidAskPage`): web pages and files, not Cra's own
    /// pages, chrome:// or an empty tab. Elsewhere the field only finds.
    public static func canAsk(page: URL?) -> Bool {
        guard let scheme = page?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }

    /// The field's placeholder, Arc's three.
    public static func placeholder(canAsk: Bool, inConversation: Bool) -> String {
        if !canAsk { return "Find in page…" }
        return inConversation ? "Ask a question…" : "Find or ask…"
    }

    public static func returnKey(query: String, matches: Int?, inConversation: Bool, canAsk: Bool) -> ReturnKey? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        guard canAsk else { return .nextMatch }
        if inConversation { return .ask }
        if let matches, matches > 0 { return .nextMatch }
        // Still waiting for the page's count: a question is the likelier reading of text with a space.
        if matches == nil { return q.contains(" ") ? .ask : .nextMatch }
        return .ask
    }

    /// Whether the Ask button shows: text typed on a page the card can answer about.
    public static func showsAskButton(query: String, canAsk: Bool) -> Bool {
        canAsk && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A quote as Arc searches for it: trimmed of whitespace and quotation marks.
    public static func trimQuote(_ quote: String) -> String {
        quote.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
    }

    /// The page's readable text, as Arc's WebPageSnapshot reads it: scripts, styles, navigation,
    /// headers, footers, forms, dialogs and what is hidden left out, the main entity or article
    /// when the page marks one. Runs in Cra's isolated world; answers {url, title, text}. Reads up to
    /// `maxPageCharacters` (the rest only counts toward the length).
    public static let pageTextScript = """
    (() => {
      const skip = 'script,style,link,svg,noscript,template,iframe,[aria-hidden=true],nav,[role=navigation],[aria-role=navigation],footer,header,[role=banner],[aria-role=banner],form,option,[role=alert],[role=dialog],[aria-role=alert],[aria-role=dialog]';
      const prefer = ['[itemprop=mainEntity]', 'article', '#content', 'main', '.reviews-content'];
      let root = null;
      for (const s of prefer) { const el = document.querySelector(s); if (el && (el.innerText || '').trim().length > 200) { root = el; break; } }
      root = root || document.body || document.documentElement;
      const block = /^(block|flex|grid|list-item|table|table-row|flow-root)$/;
      const max = \(maxPageCharacters);
      let out = '', total = 0;
      const add = (s) => { total += s.length; if (out.length < max) out += s; };
      const walk = (node) => {
        if (node.nodeType === 3) { const t = node.nodeValue.replace(/\\s+/g, ' '); if (t.trim()) add(t); return; }
        if (node.nodeType !== 1) return;
        if (node !== root && node.matches(skip)) return;
        if (node.checkVisibility && !node.checkVisibility()) return;
        const display = getComputedStyle(node).display;
        const isBlock = block.test(display) || node.tagName === 'BR';
        if (isBlock) add('\\n');
        for (const child of node.childNodes) walk(child);
        if (isBlock) add('\\n');
      };
      walk(root);
      const text = out.replace(/[ \\t]*\\n[ \\t\\n]*/g, '\\n').replace(/ {2,}/g, ' ').trim();
      return {url: location.href, title: document.title || '', text, total};
    })()
    """

    /// How much page text the script reads at most, far past what the model takes.
    public static let maxPageCharacters = 200_000
}

/// What the model is asked: Arc's rules and examples (AskInPageChat), the page between Arc's
/// tags, then the question. Arc sends it all as one message, the conversation written into it as
/// "BEGIN DIALOGUE", "Human: …", "Assistant: …". Here the rules and examples are the session's
/// instructions, the page goes with the first question, and each question and answer is a turn of
/// its own. The on-device model, given Arc's dialogue as text, writes a dialogue back: made-up
/// "Human:" questions, or the last answer again word for word (#417).
public enum AskOnPagePrompt {
    public static func rules(language: String) -> String {
        """
        You will be acting as a research assistant. I will give you the content of a webpage, and you will concisely answer \
        questions from a human using information from that page. You will provide citations for all answers using <excerpt> tags.

        \(userLine)

        RULES:
        1. stay in your role throughout the dialogue
        2. when asked a question, decide if you can answer based on information on the page. If the page answers the question, \
        directly quote the relevant sentence on the page using an <excerpt> tag on its own line. Then, summarize the answer in 10 \
        words on the next line.
        3. <excerpt> tags must be on their own line, not inline.
        4. If you can’t provide a direct quote to support your answer, make it clear that it’s just a guess.
        5. Use Markdown, not HTML, to format your answer. Always **bold** the term that answers the question.
        6. Be extremely concise. (1-sentence answers if possible).
        7. Respond in \(language).
        8. You may perform translations, summaries or other textual transformations for the user if asked.
        """
    }

    /// In place of Arc's "When I write BEGIN DIALOGUE you will enter this role, and all further input
    /// from the "Human:" will be from a user seeking answers about a webpage." The on-device model
    /// takes that as the shape of its answer and writes a dialogue (#417).
    public static let userLine = "After the page, each message is a question from a user seeking answers about the webpage."

    /// Arc's examples. Its privacy-policy one links an Arc page; Cra's links a placeholder address.
    public static let examples = """
    EXAMPLES OF RESPONSES FOR A HYPOTHETICAL WEBPAGE:
    > Why do people work in solar?
    According to J.W. Peters, president of Solar Power of Oklahoma:
    <excerpt>The environmental benefits are nice,” he said, “but most people are doing this for the financial opportunity.”</excerpt>
    So, mostly **financial, not environmental, reasons**.
    (Notice how the answer provides a direct quote from the page, on its own line, and the key answer is bold.)

    > What’s the most populous borough in NYC?
    I think it’s **Brooklyn**, but it’s not mentioned on the page.
    (Notice how it is clear that the answer comes from background knowledge, not the webpage.)

    > privacy policy
    According to the page:
    <excerpt>[Privacy Policy](https://example.com/privacy)</excerpt>
    (Notice how the answer is provided by the excerpt, in Markdown.)

    > summary
    (You would provide a brief summary)
    """

    public static func instructions(language: String) -> String {
        rules(language: language) + "\n" + examples
    }

    /// One question and its answer, earlier in the conversation.
    public struct Turn: Equatable, Sendable {
        public var question: String
        public var answer: String
        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// How many earlier answers are sent again; older ones read "[Older messages hidden]", as
    /// Arc's do, so a long conversation leaves the page room.
    public static let keptAnswers = 2
    public static let hiddenAnswer = "[Older messages hidden]"

    /// One turn the model already took: what it was asked and what it answered.
    public struct Exchange: Equatable, Sendable {
        public var prompt: String
        public var response: String
        public init(prompt: String, response: String) {
            self.prompt = prompt
            self.response = response
        }
    }

    /// What the model gets: the turns before, then the prompt it answers now. The page goes with
    /// the conversation's first question, so it comes before every answer that quotes it.
    public struct Conversation: Equatable, Sendable {
        public var earlier: [Exchange]
        public var prompt: String
    }

    /// Arc's page context (it closes <url> with </title>, kept).
    public static func context(url: String, title: String?, date: String, text: String) -> String {
        "WEBPAGE CONTEXT FOR OUR DIALOGUE:\n<url>\(url)</title>\n<current-date>\(date)</current-date>\n<title>\(title ?? "")</title>\n<content>\n\(text)\n</content>\n"
    }

    public static func conversation(url: String, title: String?, date: String, text: String, turns: [Turn], question: String) -> Conversation {
        let page = context(url: url, title: title, date: date, text: text)
        let earlier = turns.enumerated().map { i, turn in
            Exchange(prompt: i == 0 ? page + turn.question : turn.question,
                     response: i < turns.count - keptAnswers ? hiddenAnswer : turn.answer)
        }
        return Conversation(earlier: earlier, prompt: turns.isEmpty ? page + question : question)
    }

    /// What is sent besides the page and the instructions: the questions and the answers kept.
    public static func dialogue(turns: [Turn], question: String) -> String {
        let earlier = turns.enumerated().flatMap { i, turn in
            [turn.question, i < turns.count - keptAnswers ? hiddenAnswer : turn.answer]
        }
        return (earlier + [question]).joined(separator: "\n")
    }

    /// Room left for the answer, in tokens. Arc asks for up to 4,096 from a far bigger model; the
    /// on-device one has 4,096 for everything, and Arc's answers are a quote and a line.
    public static let answerTokens = 600

    /// Arc's budget for the page: three characters per token of context (at most 16,000 tokens),
    /// less the rules, the examples and 200. The on-device model's context also holds the answer,
    /// so its room comes off first; the dialogue too, since Cra sends the conversation again.
    public static func characterBudget(contextTokens: Int, instructions: String, dialogue: String) -> Int {
        let tokens = min(contextTokens, 16_000) - answerTokens
        return max(0, tokens * 3 - (instructions.count + dialogue.count + 200))
    }

    /// The page cut to `budget` characters with "…", and how much of it that is. `total` is the
    /// page's whole length when the script read only part of it. The fraction is nil when it all fits.
    public static func truncate(_ text: String, budget: Int, total: Int? = nil) -> (text: String, fractionRead: Double?) {
        let whole = max(total ?? text.count, text.count)
        guard whole > budget else { return (text, nil) }
        let cut = String(text.prefix(budget)) + "…"
        return (cut, whole == 0 ? nil : Double(min(budget, text.count)) / Double(whole))
    }

    /// The same text cut further when the model counted more tokens than it has room for: by the
    /// share that is over, and a tenth more for the estimate.
    public static func shrink(budget: Int, promptTokens: Int, allowedTokens: Int) -> Int {
        guard promptTokens > allowedTokens, promptTokens > 0 else { return budget }
        return max(0, Int(Double(budget) * Double(allowedTokens) / Double(promptTokens) * 0.9))
    }

    /// Arc's line over the answer: "This page was long, so I read the first 81%." Nil when it read it all.
    public static func fractionLine(_ fraction: Double?) -> String? {
        guard let fraction, fraction < 1 else { return nil }
        let percent = max(1, min(99, Int((fraction * 100).rounded(.down))))
        return "This page was long, so I read the first \(percent)%."
    }

    /// Arc's answer for a page with no text to speak of (49 characters or fewer).
    public static let unreadable = "Sorry, I can’t read this type of page."
    public static let failed = "Sorry, I encountered an error"
    public static let minimumText = 50

    /// The test model's answer (CRA_TIDY_FAKE_MODEL=1): the first sentence on the page that shares
    /// a word with the question, quoted the way Arc's answers are.
    public static func fakeAnswer(question: String, text: String) -> String {
        let words = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 3 }.map(String.init))
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 12 }
        guard let hit = sentences.first(where: { s in words.contains { s.lowercased().contains($0) } }) ?? sentences.first else {
            return "I think it’s **not on the page**, so this is just a guess."
        }
        return "According to the page:\n<excerpt>\(hit).</excerpt>\nSo, **\(hit.split(separator: " ").prefix(4).joined(separator: " "))**."
    }
}

/// An answer split into Arc's parts (AskInPageMessagePart): text, and quotes from the page.
public enum AskOnPageReply {
    public struct Part: Equatable, Sendable {
        public var text: String
        public var isQuote: Bool
        public init(text: String, isQuote: Bool) {
            self.text = text
            self.isQuote = isQuote
        }
    }

    /// The parts of `reply`, as far as it has come: a quote still streaming is a quote already, and a
    /// tag the model is halfway through writing is left out.
    public static func parts(_ reply: String, question: String? = nil) -> [Part] {
        var parts: [Part] = []
        var rest = Substring(clean(reply, question: question))
        func addText(_ s: Substring) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { parts.append(Part(text: t, isQuote: false)) }
        }
        while !rest.isEmpty {
            guard let open = rest.range(of: "<excerpt>") else {
                addText(dropPartialTag(rest))
                break
            }
            addText(rest[..<open.lowerBound])
            let after = rest[open.upperBound...]
            if let close = after.range(of: "</excerpt>") {
                let quote = AskOnPagePolicy.trimQuote(String(after[..<close.lowerBound]))
                if !quote.isEmpty { parts.append(Part(text: quote, isQuote: true)) }
                rest = after[close.upperBound...]
            } else {
                let quote = AskOnPagePolicy.trimQuote(String(dropPartialTag(after)))
                if !quote.isEmpty { parts.append(Part(text: quote, isQuote: true)) }
                break
            }
        }
        return parts
    }

    /// The reply without the prompt's dialogue framing, which the on-device model sometimes writes
    /// back before its answer: a "BEGIN DIALOGUE" line, the question again (as "Human: …" or as it
    /// was asked), and an "Assistant:" before the answer.
    public static func clean(_ reply: String, question: String? = nil) -> String {
        var lines = reply.components(separatedBy: "\n")
        let asked = question.map(normalized)
        while let first = lines.first {
            let t = first.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t == "BEGIN DIALOGUE" || t.hasPrefix("Human:") || t.hasPrefix("> ") { lines.removeFirst(); continue }
            // The question itself, unless it is all the model has written so far of a longer line.
            if let asked, !asked.isEmpty, normalized(t) == asked, lines.count > 1 { lines.removeFirst(); continue }
            if t.hasPrefix("Assistant:") {
                lines[0] = String(t.dropFirst("Assistant:".count)).trimmingCharacters(in: .whitespaces)
                if lines[0].isEmpty { lines.removeFirst(); continue }
            }
            break
        }
        // A streamed line still being written may be the start of "BEGIN DIALOGUE", "Human:" or the
        // question again: it waits for the rest.
        if lines.count == 1, let only = lines.first {
            if ["BEGIN DIALOGUE", "Human:", "Assistant:"].contains(where: { $0.hasPrefix(only) && !only.isEmpty }) { return "" }
            if !reply.hasSuffix("\n"), let asked, !normalized(only).isEmpty, asked.hasPrefix(normalized(only)) { return "" }
        }
        return lines.joined(separator: "\n")
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// What Find on Page searches for, in turn, until the page has it: the whole quote, then its first
    /// sentence, then its first eight words. A page's own marks between sentences (Wikipedia's "[3]")
    /// and the model's small slips keep a whole quote from matching.
    public static func findCandidates(_ quote: String) -> [String] {
        let whole = findText(quote)
        var out = [whole]
        if let end = whole.firstIndex(where: { ".!?".contains($0) }), whole.index(after: end) < whole.endIndex {
            let sentence = findText(String(whole[...end]))
            if sentence.count >= 12 { out.append(sentence) }
        }
        let words = whole.split(separator: " ")
        if words.count > 8 { out.append(words.prefix(8).joined(separator: " ")) }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The text without a tag cut off at its end ("<exc", "</excer").
    static func dropPartialTag(_ s: Substring) -> Substring {
        guard let lt = s.lastIndex(of: "<") else { return s }
        let tail = s[lt...]
        if !tail.contains(">"), "</excerpt>".hasPrefix(tail) || "<excerpt>".hasPrefix(tail) { return s[..<lt] }
        return s
    }

    /// A quote's text for the page's find: Markdown links and emphasis read as their words, which is
    /// what the page shows.
    public static func findText(_ quote: String) -> String {
        var s = quote.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        s = AskOnPagePolicy.trimQuote(s)
        // A trailing ellipsis or full stop the model added isn't always the page's.
        while let last = s.last, ".…".contains(last) { s.removeLast() }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
