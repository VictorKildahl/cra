import CraCore
@testable import CraCore
import Testing

struct CommandBarScoreTests {
    func key(_ title: String, _ url: String, _ host: String) -> CommandBarScore.Key {
        CommandBarScore.Key(title: title.lowercased(), url: url.lowercased(), host: host.lowercased())
    }

    /// GitHub #617: scoring 5,000 tabs on Swift strings took about 16 ms a keystroke. The byte path gives
    /// the String path's score for every query and text, checked here on 20,000 random pairs.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/617"))
    func bytesScoreAsStringsDo() {
        var rng = SplitMix(seed: 617)
        let alphabet = Array("abcdefghij klmnop-./:_0123456789".utf8)
        func word(_ n: Int) -> String { String(decoding: (0..<n).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }, as: UTF8.self) }
        for _ in 0..<20_000 {
            let title = word(Int(rng.next() % 40)), url = word(Int(rng.next() % 50)), host = word(Int(rng.next() % 12))
            let k = key(title, url, host)
            // Queries from the text itself (prefixes, slices) and random ones.
            let source = [title, url, host][Int(rng.next() % 3)]
            let start = source.isEmpty ? 0 : Int(rng.next() % UInt64(source.count))
            let slice = String(source.dropFirst(start).prefix(1 + Int(rng.next() % 6)))
            for q in [slice, word(1 + Int(rng.next() % 5)), String(title.prefix(3))] where !q.isEmpty {
                let q = q.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { continue }
                #expect(CommandBarScore.score(q, k) == CommandBarScore.stringScore(q, k), "\(q) in \(title) | \(url) | \(host)")
            }
        }
    }

    @Test func knownScores() {
        let k = key("React Hooks Guide - GitHub", "github.com/facebook/react", "www.github.com")
        #expect(CommandBarScore.score("react", k) == 100)
        #expect(CommandBarScore.score("hooks", k) == 85)
        #expect(CommandBarScore.score("ooks", k) == 65)
        #expect(CommandBarScore.score("rhg", k) > 25)
        #expect(CommandBarScore.score("git", k) == 95)
        #expect(CommandBarScore.score("react guide", k) == 75)
        #expect(CommandBarScore.score("react -", k) == CommandBarScore.stringScore("react -", k))
        // A word's prefix never reaches past the word.
        #expect(CommandBarScore.score("hooks-", key("react hooks- x", "", "")) == CommandBarScore.stringScore("hooks-", key("react hooks- x", "", "")))
        // Other text goes through String.
        let accented = key("Café Crème", "cafe.example", "cafe.example")
        #expect(CommandBarScore.score("café", accented) == 100 && CommandBarScore.score("crè", accented) == 85)
        #expect(CommandBarScore.score("line", key("first\r\nline", "", "")) == CommandBarScore.stringScore("line", key("first\r\nline", "", "")))
    }
}

/// A small seeded generator, so the random pairs are the same every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
