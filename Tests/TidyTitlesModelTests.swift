import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidy Tab Titles' model adapter. Without arguments: the answer schema is Arc's. With `--real`:
/// asks the Mac's own model (needs Apple Intelligence) for Arc's recorded renames and titles held
/// out of the prompt, picks each name as a 230 pt sidebar row does, and prints the names.
@main
struct TidyTitlesModelTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    @MainActor
    static func main() async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let schema = String(decoding: try JSONEncoder().encode(TidyTitleAnswer.generationSchema), as: UTF8.self)
            expect(schema.contains("The title translated and filtered to remove the cruft. No word limit.")
                   && schema.contains("The title rewritten in 1-3 words"),
                   "the answer's fields carry Arc's schema comments word for word")
            let filtered = schema.range(of: "\"filtered\""), rewritten = schema.range(of: "\"rewritten\"")
            expect(filtered != nil && rewritten != nil, "the answer has filtered and rewritten")
            if CommandLine.arguments.contains("--real") { try await realSamples() }
        }
        #endif
        if failures > 0 { print("Tidy titles model: \(failures) failed"); exit(1) }
        print("Tidy titles model: checks passed")
    }

    /// Arc's renames in Victor's Arc (arc-reverse-engineering.md), then titles judged by Arc's own
    /// rules. The model varies between macOS versions, so this prints rather than asserts names.
    static let samples: [(title: String, url: String, good: [String])] = [
        ("Climate - BBC News", "https://www.bbc.com/news/science_and_environment", ["Climate News"]),
        ("Foundation Models | Apple Developer Documentation", "https://developer.apple.com/documentation/foundationmodels", ["Foundation Models"]),
        ("IT Career Paths - IT General - Confluence", "https://acme.atlassian.net/wiki/spaces/IT/pages/1", ["IT Career Paths"]),
        ("Personal apps | Heroku", "https://dashboard.heroku.com/apps", ["Heroku"]),
        ("Deltagere ‹ Grønne tanker — WordPress", "https://groenne.dk/wp-admin/admin.php?page=participants", ["Grønne tanker"]),
        ("Convert SVG to PNG - SVG Viewer", "https://www.svgviewer.dev/svg-to-png", ["SVG to PNG"]),
        ("Free Backlink Checker by Ahrefs: Check Backlinks to Any Site", "https://ahrefs.com/backlink-checker", ["Ahrefs"]),
        ("Jupiter - Wikipedia", "https://en.wikipedia.org/wiki/Jupiter", ["Jupiter"]),
        ("Pasta alla Norma Recipe | Bon Appétit", "https://www.bonappetit.com/recipe/pasta-alla-norma", ["Pasta alla Norma"]),
        ("How to Train Your Dragon (2025) - IMDb", "https://www.imdb.com/title/tt26743210/", ["How to Train Your Dragon", "How to Train Your Dragon (2025)", "How to Train Your Dragon 2025"]),
        ("Linear – Plan and build products", "https://linear.app/", ["Linear"]),
        ("Pull requests · VictorKildahl/cra", "https://github.com/VictorKildahl/cra/pulls", ["cra Pull Requests", "Pull Requests", "cra PRs"]),
        ("Swift Concurrency: Update an app - WWDC21 - Videos - Apple Developer", "https://developer.apple.com/videos/play/wwdc2021/10194/", ["Swift Concurrency", "Swift Concurrency Update", "Swift Concurrency: Update an app"]),
        ("Inbox (3) - victor@example.com - Gmail", "https://mail.google.com/mail/u/0/#inbox", ["Gmail", "Gmail Inbox", "Inbox"]),
        ("Lisbon Travel Guide: Best Things to Do in 2026 | Lonely Planet", "https://www.lonelyplanet.com/portugal/lisbon", ["Lisbon", "Lisbon Travel", "Things to Do in Lisbon", "Best Things to Do in Lisbon"]),
        ("Sådan søger du SU | SU.dk", "https://www.su.dk/su/saadan-soeger-du-su", ["Applying for SU", "How to Apply for SU", "Apply for SU", "SU Application"]),
        ("東京の天気 - Yahoo!天気・災害", "https://weather.yahoo.co.jp/weather/jp/13/4410.html", ["Tokyo Weather"]),
        ("Stripe Dashboard", "https://dashboard.stripe.com/", ["Stripe", "Stripe Dashboard"]),
    ]

    @MainActor
    static func realSamples() async throws {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14)
        label.frame.size.width = 230 + 2 * 2
        let layout = TidyTitleLayout(label: label, inset: 2)
        let instructions = TidyTitles.instructions(language: "English")
        var good = 0
        for sample in samples {
            let prompt = TidyTitles.prompt(title: sample.title, url: sample.url)
            let answer = try await TidyTitlesModel.respond(instructions: instructions, prompt: prompt,
                                                           responseLimit: TidyTitles.responseTokenLimit)
            let name = layout.select(TidyTitles.candidates(answer), shown: "") ?? "(none)"
            let hit = sample.good.contains { $0.lowercased() == name.lowercased() }
            if hit { good += 1 }
            print("\(hit ? "✓" : "·") \(sample.title) → \(name)   [filtered: \(answer.filtered) | rewritten: \(answer.rewritten)]")
        }
        print("real model: \(good) of \(samples.count) names as expected (11 on macOS 26.7.2, 16 Nov 2026)")
    }
}
