import Foundation

/// A Boost that travels between Macs: a gallery boost (`boosts/<slug>/boost.json` in this repo,
/// listed on crabrowser.app/boosts), a Share Boost… link (`crabrowser.app/boost#…`) and the site's
/// Open in Cra button (`cra-boost:…`). Arc kept shared boosts on arc.net; Cra has no server, so the
/// boost itself rides in the link after the `#` (or after `cra-boost:`), deflated and base64url'd
/// like `FolderShareLink`, and the gallery's file is the same JSON.
///
/// Look only: a shared boost restyles a site and hides parts of it, it never runs code there. The
/// format has no field for a boost's JavaScript (a `js` key in a link is ignored), and the CSS may
/// not fetch anything (`url()`, `@import`, `image-set()`…): a selector like
/// `input[value^="a"] { background: url(…) }` would send what you type to whoever wrote it. Whatever
/// `problems` finds keeps a boost out of the gallery and makes a link refuse to install.
///
/// The format is a promise: links people already sent keep installing. A change adds a new `v`.
///
///     {"v":1,"name":"Hide Shorts","host":"youtube.com","zapped":["ytd-reel-shelf-renderer"]}
public struct SharedBoost: Codable, Equatable, Sendable {
    public static let version = 1
    /// What Share Boost… copies; the site's page shows the boost and its Open in Cra button.
    public static let linkPrefix = Sharing.base + "/boost#"
    /// What Open in Cra opens: macOS hands it to Cra, which asks before adding anything.
    public static let installScheme = "cra-boost"
    public static let nameLimit = 60
    public static let aboutLimit = 280
    public static let cssLimit = 20_000
    public static let zappedLimit = 200

    public var v: Int
    public var name: String
    /// The site, a host without "www.", as `Boost.host`.
    public var host: String
    /// One or two sentences: what it changes and why.
    public var about: String?
    /// Who made it: a GitHub user name in the gallery.
    public var by: String?
    /// A page where the change shows (the gallery's before/after pictures are taken there).
    public var preview: String?
    public var hue: Double?
    public var strength: Double?
    public var invert: Bool?
    public var contrast: Double?
    public var brightness: Double?
    public var saturation: Double?
    /// One of `Boost.fonts` by name.
    public var font: String?
    public var textScale: Double?
    /// `Boost.TextCase`'s raw value.
    public var textCase: String?
    public var zapped: [String]?
    public var css: String?

    public init(name: String, host: String, about: String? = nil, by: String? = nil, preview: String? = nil) {
        v = Self.version
        self.name = name
        self.host = Boost.siteHost(host)
        self.about = about
        self.by = by
        self.preview = preview
    }

    /// A boost from the editor, as it is shared: its look, never its JavaScript. Values at the
    /// site's own are left out, so the link is as short as the boost.
    public init(_ boost: Boost) {
        self.init(name: boost.name, host: boost.host)
        if boost.strength > 0 { hue = boost.hue; strength = boost.strength }
        if boost.invert { invert = true }
        if boost.contrast != 50 { contrast = boost.contrast }
        if boost.brightness != 50 { brightness = boost.brightness }
        if boost.saturation != 50 { saturation = boost.saturation }
        if let f = boost.font, Boost.fonts.indices.contains(f) { font = Boost.fonts[f] }
        if boost.textScale != 1 { textScale = boost.textScale }
        if boost.textCase != .none { textCase = boost.textCase.rawValue }
        if !boost.zapped.isEmpty { zapped = boost.zapped }
        let trimmed = boost.css.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { css = boost.css }
    }

    /// The boost to keep, as a new one. Nothing of the sender's but its look comes in.
    public func boost() -> Boost {
        var b = Boost(host: host, name: name)
        b.hue = hue ?? 0
        b.strength = strength ?? 0
        b.invert = invert ?? false
        b.contrast = contrast ?? 50
        b.brightness = brightness ?? 50
        b.saturation = saturation ?? 50
        b.font = font.flatMap { Boost.fonts.firstIndex(of: $0) }
        b.textScale = textScale ?? 1
        b.textCase = textCase.flatMap(Boost.TextCase.init(rawValue:)) ?? .none
        b.zapped = zapped ?? []
        b.css = css ?? ""
        return b
    }

    /// Whether it changes anything at all.
    public var isEmpty: Bool { boost().stylesheet.isEmpty }

    // MARK: What may travel

    /// Why this boost can't be shared or installed; empty when it can.
    public var problems: [String] {
        var out: [String] = []
        if v != Self.version { out.append("Made by a newer Cra (format \(v)).") }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { out.append("It has no name.") }
        if n.count > Self.nameLimit { out.append("Its name is longer than \(Self.nameLimit) characters.") }
        if (about?.count ?? 0) > Self.aboutLimit { out.append("Its description is longer than \(Self.aboutLimit) characters.") }
        if !Self.isHost(host) { out.append("“\(host)” isn’t a site.") }
        if let by, !Self.isGitHubName(by) { out.append("“\(by)” isn’t a GitHub user name.") }
        if let preview, Self.webURL(preview) == nil { out.append("Its preview page isn’t a web address.") }
        func range(_ value: Double?, _ r: ClosedRange<Double>, _ what: String) {
            if let value, !r.contains(value) { out.append("\(what) is out of range.") }
        }
        range(hue, 0...1, "The hue")
        range(strength, 0...1, "The tint")
        range(contrast, 0...100, "Contrast")
        range(brightness, 0...100, "Brightness")
        range(saturation, 0...100, "Saturation")
        range(textScale, 0.5...3, "The text size")
        if let font, !Boost.fonts.contains(font) { out.append("“\(font)” isn’t one of the editor’s fonts.") }
        if let textCase, Boost.TextCase(rawValue: textCase) == nil { out.append("“\(textCase)” isn’t a text case.") }
        if (zapped?.count ?? 0) > Self.zappedLimit { out.append("It hides more than \(Self.zappedLimit) things.") }
        for selector in zapped ?? [] {
            if selector.count > 500 || selector.contains(where: { "{};<>".contains($0) }) || selector.contains("/*") {
                out.append("“\(selector.prefix(40))” isn’t a selector.")
            } else if let issue = Self.fetchIssue(selector) {
                out.append(issue)
            }
        }
        if let css {
            if css.count > Self.cssLimit { out.append("Its CSS is longer than \(Self.cssLimit) characters.") }
            if let issue = Self.fetchIssue(css) { out.append(issue) }
        }
        if out.isEmpty && isEmpty { out.append("It doesn’t change anything.") }
        return out
    }

    /// CSS functions that load something: a picture, a font, another stylesheet. Each one sends a
    /// request a page's own content can steer.
    static let fetchingFunctions: Set<String> = [
        "url", "src", "image", "image-set", "cross-fade", "element", "expression", "paint",
    ]

    /// Why `css` could load or run something, nil when it can't. A backslash may only escape
    /// punctuation (`.md\:hidden`): `\75 rl(` and `\url(` both spell `url(` to the CSS parser.
    static func fetchIssue(_ css: String) -> String? {
        let lower = css.lowercased()
        for (i, c) in zip(lower.indices, lower) where c == "\\" {
            let next = lower.index(after: i)
            guard next < lower.endIndex, let ch = lower[next].unicodeScalars.first,
                  ch.isASCII, CharacterSet.punctuationCharacters.union(.symbols).contains(ch)
            else { return "Its CSS escapes a letter or number (only punctuation may be escaped)." }
        }
        for banned in ["@import", "javascript:", "-moz-binding", "behavior:", "behavior :"] where lower.contains(banned) {
            return "Its CSS uses \(banned), which can load or run something."
        }
        // A function token is a name right before "(" (no space or comment between them).
        var name = ""
        for c in lower {
            if c == "(" {
                let bare = name.replacingOccurrences(of: #"^-[a-z]+-"#, with: "", options: .regularExpression)
                if fetchingFunctions.contains(bare) { return "Its CSS uses \(name)(), which loads from the web." }
                name = ""
            } else if c.isLetter || c.isNumber || c == "-" || c == "_" {
                name.append(c)
            } else {
                name = ""
            }
        }
        return nil
    }

    static func isHost(_ host: String) -> Bool {
        guard host.count <= 253, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              !host.hasPrefix("www."), host == host.lowercased()
        else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    static func isGitHubName(_ name: String) -> Bool {
        (1...39).contains(name.count) && !name.hasPrefix("-") && !name.hasSuffix("-")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func webURL(_ string: String) -> String? { FolderShareLink.webURL(string) }

    // MARK: The link

    /// The boost packed for a link: the part after `#` or `cra-boost:`.
    public var payload: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(self),
              let deflated = try? (json as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return FolderShareLink.base64URL(deflated)
    }

    /// Share Boost…'s link, nil when the boost can't travel.
    public var link: String? { problems.isEmpty ? payload.map { Self.linkPrefix + $0 } : nil }

    /// The Open in Cra address for this boost.
    public var installURL: String? { problems.isEmpty ? payload.map { Self.installScheme + ":" + $0 } : nil }

    /// The boost in a crabrowser.app/boost link or a cra-boost: address, nil for anything else.
    /// It may still have `problems`: the caller says why it won't install.
    public static func from(link: String) -> SharedBoost? {
        let packed: Substring
        if link.hasPrefix(linkPrefix) {
            packed = link.dropFirst(linkPrefix.count)
        } else if link.lowercased().hasPrefix(installScheme + ":") {
            packed = link.dropFirst(installScheme.count + 1).drop { $0 == "/" }
        } else {
            return nil
        }
        // A whole link is at most 64 KB, well past the longest boost.
        guard packed.count <= 65_536, let data = FolderShareLink.data(base64URL: String(packed)),
              let json = try? (data as NSData).decompressed(using: .zlib) as Data, json.count <= 262_144
        else { return nil }
        return from(json: json)
    }

    /// A gallery `boost.json`, or a link's unpacked JSON.
    public static func from(json: Data) -> SharedBoost? {
        guard var boost = try? JSONDecoder().decode(SharedBoost.self, from: json) else { return nil }
        boost.host = Boost.siteHost(boost.host)
        return boost
    }
}
