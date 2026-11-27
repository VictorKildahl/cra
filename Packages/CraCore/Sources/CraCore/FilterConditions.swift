import Foundation

/// A filter list's `!#if` blocks (uBlock Origin's and AdGuard's preprocessor): `!#if env_chromium`, `!#if
/// !cap_html_filtering`, `!#if (env_mobile || adguard)`, closed by `!#endif`, with `!#else`. Cra reads a block
/// when its condition holds for Cra: a Chromium browser on the Mac that runs the list's scriptlets itself (#845),
/// and not uBlock Origin, uBO Lite, AdGuard or Adblock Plus, whose own blocks use features only they have.
/// Before #845 every `!#if` block was skipped, so uBlock filters' Chromium-only lines were lost.
public enum FilterConditions {
    /// Tokens true for Cra. Every other token is false.
    public static let trueTokens: Set<String> = ["env_chromium", "env_mv3"]

    /// Whether `expression` (the text after `!#if `) holds.
    public static func holds(_ expression: String) -> Bool {
        var tokens = tokenize(expression)
        let value = parseOr(&tokens)
        return value ?? false
    }

    private static func tokenize(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        let chars = Array(text)
        var i = 0
        func flush() { if !word.isEmpty { out.append(word); word = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "(" || c == ")" || c == "!" { flush(); out.append(String(c)) }
            else if c == "&" || c == "|" {
                flush()
                out.append(String(c) + String(c))
                if i + 1 < chars.count, chars[i + 1] == c { i += 1 }
            } else if c.isWhitespace { flush() }
            else { word.append(c) }
            i += 1
        }
        flush()
        return out
    }

    private static func parseOr(_ t: inout [String]) -> Bool? {
        guard var left = parseAnd(&t) else { return nil }
        while t.first == "||" {
            t.removeFirst()
            guard let right = parseAnd(&t) else { return nil }
            left = left || right
        }
        return left
    }

    private static func parseAnd(_ t: inout [String]) -> Bool? {
        guard var left = parseNot(&t) else { return nil }
        while t.first == "&&" {
            t.removeFirst()
            guard let right = parseNot(&t) else { return nil }
            left = left && right
        }
        return left
    }

    private static func parseNot(_ t: inout [String]) -> Bool? {
        guard let first = t.first else { return nil }
        if first == "!" {
            t.removeFirst()
            return parseNot(&t).map { !$0 }
        }
        if first == "(" {
            t.removeFirst()
            let value = parseOr(&t)
            guard t.first == ")" else { return nil }
            t.removeFirst()
            return value
        }
        t.removeFirst()
        return trueTokens.contains(first.lowercased())
    }

    /// The lines a reader keeps: `!#if` blocks whose condition fails (and the false branch of `!#else`) dropped,
    /// with how many filter lines were left out.
    public static func active(_ lines: [Substring]) -> (lines: [Substring], skipped: Int) {
        var kept: [Substring] = []
        var skipped = 0
        // One entry per open block: whether its lines are read.
        var stack: [Bool] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("!#if ") {
                let parentOn = stack.last ?? true
                stack.append(parentOn && holds(String(line.dropFirst(5))))
                continue
            }
            if line == "!#else" {
                if let on = stack.popLast() {
                    let parentOn = stack.last ?? true
                    stack.append(parentOn && !on)
                }
                continue
            }
            if line == "!#endif" {
                _ = stack.popLast()
                continue
            }
            if stack.last ?? true { kept.append(raw) } else if !line.hasPrefix("!") && !line.isEmpty { skipped += 1 }
        }
        return (kept, skipped)
    }
}
