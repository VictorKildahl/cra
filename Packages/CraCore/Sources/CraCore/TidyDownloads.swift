import Foundation

/// Arc Max's Tidy Downloads (renameDownloads), on the Mac's own Apple Intelligence model: a finished
/// download gets a short, readable name from its file name, the tab's title and the site (Arc 1.171's
/// beginRename(…defaultFilename:sourceUrl:webContentsTitle:referrerTitle:)). This decides what the
/// model is asked and which answers may become a file's name; renaming the file is the app's.
public enum TidyDownloads {
    static let maximumLength = 80

    /// Captured from the actual source tab, before it navigates or disappears. Custom sidebar
    /// names and pinned home titles are not the title of the page that initiated the download.
    public struct Source {
        public let title: String
        public let url: String

        public init(tab: TabData, referrer: TabData? = nil) {
            let title = bounded(tab.savedTitle, characters: 256, bytes: 768)
            self.title = title.isEmpty ? bounded(referrer?.savedTitle ?? "", characters: 256, bytes: 768) : title
            url = bounded(tab.url, characters: 1024, bytes: 2048)
        }
    }

    /// Short local-model input, independently bounded from the actual on-disk filename.
    public struct Request {
        public let file: String
        public let sourceTitle: String
        public let sourceDomain: String
        public let responseLanguage: String

        public init(file: String, source: Source? = nil, downloadURL: String, language: String) {
            self.file = bounded(file, characters: 128, bytes: 512)
            sourceTitle = source?.title ?? ""
            let url = bounded(source.flatMap { $0.url.isEmpty ? nil : $0.url } ?? downloadURL, characters: 1024, bytes: 2048)
            sourceDomain = bounded(URL(string: url)?.host?.lowercased() ?? url, characters: 512, bytes: 1024)
            let language = bounded(language, characters: 64, bytes: 128)
            responseLanguage = language.isEmpty ? "English" : language
        }
    }

    /// Arc 1.173's system prompt, word for word (strings in Arc's binary, 16 Nov 2026), up to the
    /// JSON schema it asks for: Cra's model returns `newName` through guided generation instead.
    public static let instructions = """
    I am downloading a file. Rewrite its filename to be helpful, concise and readable. 2-4 words.
    - Keep informative names mostly the same. For non-informative names, add information from the tab title or website.
    - Remove machine-generated cruft, like IDs, (1), (copy), etc.
    - Clean up messy text, especially dates. Make timestamps concise, human readable, and remove seconds.
    - Clean up text casing and letter spacing to make it easier to read.
    Some examples, in the form "original name, tab title, domain -> new name"
    """ + "\n" + examples.map { "- '\($0.file)', '\($0.title)', '\($0.site)' -> '\($0.name)' (\($0.why))" }.joined(separator: "\n")

    /// Arc's nine examples with its reasons; the Gmail example's address is de-identified.
    public static let examples: [(file: String, title: String, site: String, name: String, why: String)] = [
        ("Arc-1.6.0-41215.dmg", "Arc from The Browser Company", "arc.net", "Arc 1.6.0 41215.dmg", "same info, easier to read"),
        ("swift-chat-main.zip", "huggingface/swift-chat: Mac app to demonstrate swift-transformers", "github.com", "swift-chat main.zip",
         "same info, easier to read"),
        ("folio_option3_6691488.PDF", "Your Guest Stay Folio from the LINE LA 08-14-23", "mail.google.com", "Line LA Folio, Aug 14.pdf",
         "remove ID numbers, make easier to read, add helpful info from tab title"),
        ("image.png", "Feedback: Card border radius - editor@example.com - Gmail", "mail.google.com", "Card border radius feedback.png",
         "remove non-useful words like 'image', add helpful info from tab title"),
        ("Brooklyn_Bridge_September_2022_008.jpg", "nyc bridges - Google Images", "images.google.com", "Brooklyn Bridge Sept 2022.jpg",
         "keep useful information, clean up formatting, remove '008' ID"),
        ("AdobeStock_184679416.jpg", "ladybug - Google Images", "images.google.com", "Ladybug.jpg",
         "add info from title, remove 'AdobeStock' cruft"),
        ("CleanShot 2023-08-17 at 19.51.05@2x.png", "dogfooding - The Browser Company - Slack", "app.slack.com",
         "CleanShot Aug 17 from dogfooding.png", "keep useful info, trim date, add source from title"),
        ("Screenshot 2023-09-26 at 11.12.18\u{202F}PM", "DM with Nate - Twitter", "twitter.com", "Sept 26 Screenshot from Nate.png",
         "keep useful info, trim date, add source from title"),
        ("image0.png", "Nate - Slack", "files.slack.com", "Image from Nate via Slack.png", "add info from title"),
    ]

    /// Arc's request: the three values in quotes, one per line. Each value is bounded and has no
    /// line breaks or control characters (`bounded`), so a name or title can't add a line of its own.
    public static func prompt(_ request: Request) -> String {
        "Original filename: '\(request.file)'\nSource tab title: '\(request.sourceTitle)'\nSource domain: '\(request.sourceDomain)'"
    }

    /// Arc ends its instructions with the language to answer in.
    public static func instructions(for request: Request) -> String {
        instructions + "\nWrite responses (but not JSON keys) in \(request.responseLanguage)"
    }

    /// The model's answer as a file name in the same folder, or nil when it isn't usable: empty,
    /// hidden (".…"), the same name, or with path characters. The original extension stays.
    public static func clean(_ answer: String, original: String) -> String? {
        var s = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’`")))
        s = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Arc 1.171's 0x1002d488c/0x1002d6b38: replace the model's final-dot suffix
        // with the original's, including an empty suffix or a trailing dot. A suffix with a
        // space or no letter is part of the name ("Arc 1.6.0 41215", "Notes v2.1"), not an extension.
        if let dot = s.lastIndex(of: ".") {
            let suffix = s[s.index(after: dot)...]
            if suffix.isEmpty || (!suffix.contains(where: \.isWhitespace) && suffix.contains(where: \.isLetter)) {
                s = String(s[..<dot])
            }
        }
        guard !s.isEmpty, !s.hasPrefix(".") else { return nil }
        s += original.lastIndex(of: ".").map { String(original[$0...]) } ?? ""
        guard s.count <= maximumLength, s != original else { return nil }
        return s
    }

    /// Arc's free sibling name: the proposal, then "Report (1).pdf" through "Report (100).pdf".
    /// No name is returned when every candidate is occupied.
    public static func unique(_ name: String, existing: (String) -> Bool) -> String? {
        guard existing(name) else { return name }
        let dot = name.lastIndex(of: ".") ?? name.endIndex
        let stem = name[..<dot], suffix = name[dot...]
        for n in 1...100 {
            let candidate = "\(stem) (\(n))\(suffix)"
            if !existing(candidate) { return candidate }
        }
        return nil
    }

    /// Bound before normalization; whole graphemes retain ZWJ/ZWNJ and cannot bypass byte caps.
    private static func bounded(_ value: String, characters: Int, bytes: Int) -> String {
        var prefix = "", size = 0, length = 0
        for character in value {
            let count = String(character).utf8.count
            guard length < characters, size + count <= bytes else { break }
            prefix.append(character)
            size += count
            length += 1
        }
        return String(prefix.unicodeScalars.filter { $0.properties.generalCategory != .control || CharacterSet.whitespacesAndNewlines.contains($0) })
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
