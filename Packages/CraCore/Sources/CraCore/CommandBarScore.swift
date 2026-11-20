import Foundation

/// How well typed text matches a tab, an archived tab or a visited page in the command bar (GitHub #617).
/// The same rules SuggestionEngine had; at 5,000 tabs they ran on Swift strings, grapheme by grapheme,
/// and scoring alone took about 16 ms a keystroke. An ASCII query against ASCII text (nearly every title
/// and address) is now matched on its UTF-8 bytes, which gives the same answer; anything else still goes
/// through String.
public enum CommandBarScore {
    /// One row's text, prepared once per bar opening.
    public struct Key: Sendable {
        public let title: String
        public let words: [Substring]
        public let url: String
        public let host: String
        public let bareHost: String
        let titleBytes: [UInt8], urlBytes: [UInt8], hostBytes: [UInt8], bareHostBytes: [UInt8]
        /// Where each word starts in `titleBytes` (ASCII titles only).
        let wordStarts: [Int]
        let ascii: Bool

        /// `title` and `url` already lowercased; `host` from the address, lowercased.
        public init(title: String, url: String, host: String) {
            self.title = title
            words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            self.url = url
            self.host = host
            bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            titleBytes = Array(title.utf8); urlBytes = Array(url.utf8); hostBytes = Array(host.utf8); bareHostBytes = Array(bareHost.utf8)
            // Printable ASCII only: "\r\n" is one Character to String, two bytes here.
            ascii = [title, url, host].allSatisfy { $0.utf8.allSatisfy(Self.printable) }
            var starts: [Int] = []
            if ascii {
                var inWord = false
                for (i, b) in titleBytes.enumerated() {
                    let wordByte = (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A)
                    if wordByte && !inWord { starts.append(i) }
                    inWord = wordByte
                }
            }
            wordStarts = starts
        }

        static func printable(_ b: UInt8) -> Bool { b >= 0x20 && b < 0x80 }
    }

    static func isWordByte(_ b: UInt8) -> Bool { (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) }

    /// The score for lowercased query `q`: 0 when nothing matches.
    public static func score(_ q: String, _ key: Key) -> Double {
        if key.ascii, q.utf8.allSatisfy(Key.printable) { return asciiScore(Array(q.utf8), key) }
        return stringScore(q, key)
    }

    // MARK: Bytes

    static func asciiScore(_ q: [UInt8], _ key: Key) -> Double {
        let t = key.titleBytes, u = key.urlBytes
        var score = 0.0
        if q.contains(0x20) {
            let tokens = q.split(separator: 0x20, omittingEmptySubsequences: true).map(Array.init)
            if tokens.count > 1 {
                // A token holds no space, so it is in "title url" only if it is in one of them.
                let hits = tokens.filter { contains(t, $0) || contains(u, $0) }.count
                if hits == tokens.count { score = 75 } else if hits > 0 { score = 30 * Double(hits) / Double(tokens.count) }
                if hasPrefix(t, q) { score = 95 }
                return score
            }
        }
        if hasPrefix(t, q) { score = 100 }
        // A word is word characters only: a query with anything else is no word's prefix; one without that
        // matches at a word's start stays inside that word.
        else if q.allSatisfy(isWordByte), key.wordStarts.contains(where: { hasPrefix(t, q, at: $0) }) { score = 85 }
        else if contains(t, q) { score = 65 }
        else if let f = fuzzy(q, in: t) { score = 25 + 25 * f }
        if hasPrefix(key.bareHostBytes, q) || hasPrefix(key.hostBytes, q) { score = max(score, 95) }
        else if contains(key.bareHostBytes, q) { score = max(score, 70) }
        else if contains(u, q) { score = max(score, 55) }
        return score
    }

    static func hasPrefix(_ s: [UInt8], _ p: [UInt8], at start: Int = 0) -> Bool {
        guard s.count - start >= p.count else { return false }
        for i in 0..<p.count where s[start + i] != p[i] { return false }
        return true
    }

    static func contains(_ s: [UInt8], _ p: [UInt8]) -> Bool {
        if p.isEmpty { return true }
        guard s.count >= p.count else { return false }
        return s.withUnsafeBytes { sb in p.withUnsafeBytes { pb in memmem(sb.baseAddress, sb.count, pb.baseAddress, pb.count) != nil } }
    }

    static func fuzzy(_ q: [UInt8], in text: [UInt8]) -> Double? {
        guard q.count >= 3 else { return nil }
        var i = 0, gaps = 0, inGap = false
        for c in q {
            var found = false
            while i < text.count {
                let x = text[i]; i += 1
                if x == c { found = true; break }
                inGap = true
            }
            if !found { return nil }
            if inGap { gaps += 1; inGap = false }
        }
        return max(0, 1 - Double(gaps) / Double(q.count))
    }

    // MARK: Strings (any other text, and the reference for the byte path)

    static func stringScore(_ q: String, _ key: Key) -> Double {
        let t = key.title, u = key.url, host = key.host, bareHost = key.bareHost
        var score = 0.0
        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            let hay = t + " " + u
            let hits = tokens.filter { hay.contains($0) }.count
            if hits == tokens.count { score = 75 } else if hits > 0 { score = 30 * Double(hits) / Double(tokens.count) }
            if t.hasPrefix(q) { score = 95 }
            return score
        }
        if t.hasPrefix(q) { score = 100 }
        else if key.words.contains(where: { $0.hasPrefix(q) }) { score = 85 }
        else if t.contains(q) { score = 65 }
        else if let f = fuzzy(q, in: t) { score = 25 + 25 * f }
        if bareHost.hasPrefix(q) || host.hasPrefix(q) { score = max(score, 95) }
        else if bareHost.contains(q) { score = max(score, 70) }
        else if u.contains(q) { score = max(score, 55) }
        return score
    }

    static func fuzzy(_ q: String, in text: String) -> Double? {
        guard q.count >= 3 else { return nil }
        var it = text.makeIterator()
        var gaps = 0
        var inGap = false
        for c in q {
            var found = false
            while let x = it.next() {
                if x == c { found = true; break }
                inGap = true
            }
            if !found { return nil }
            if inGap { gaps += 1; inGap = false }
        }
        return max(0, 1 - Double(gaps) / Double(q.count))
    }
}
