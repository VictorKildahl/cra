import Foundation
import CoreGraphics

/// What Cra shows while an MCP agent works in a tab ("the cursor is the face", 17 Nov 2026): a
/// little face marks the tab's sidebar row, Cra's toast leads with it and says what the agent
/// does, and, only while the user is on that tab, the face is the agent's cursor and glides to
/// what it clicks, so a page never changes without the user seeing what was clicked. These are the
/// decisions; the app draws them.
public enum MCPAgentPresence {
    /// The sidebar face stays this long after the agent's last call in the tab.
    public static let lingers: TimeInterval = 8
    /// The cursor fades this long after its last move or press.
    public static let cursorLingers: TimeInterval = 2.5
    /// A watched pointer rests on its target this long before it presses, so the user sees what
    /// is about to be clicked.
    public static let dwell: TimeInterval = 0.15
    /// The longest quoted page text in the toast (a ref's accessible name is the page's own words).
    public static let targetLimit = 32

    /// The toast's text for a call. `target` is the accessible name of the element it acts on,
    /// when the agent named one by ref; `site` is the tab's host.
    public static func activity(agent: String, tool: String, arguments: [String: Any], target: String?, site: String?) -> String {
        let quoted = target.flatMap(quote)
        let on = site.map { " on \($0)" } ?? ""
        let what: String
        switch tool {
        case "page_click":
            what = quoted.map { "is clicking \($0)" } ?? "is clicking\(on)"
        case "page_hover":
            what = quoted.map { "is pointing at \($0)" } ?? "is moving the pointer\(on)"
        case "page_type", "page_fill":
            what = quoted.map { "is typing in \($0)" } ?? "is typing\(on)"
        case "page_press":
            what = (arguments["key"] as? String).flatMap { keys($0, modifiers: arguments["modifiers"] as? String) }.map { "is pressing \($0)" }
                ?? "is pressing a key"
        case "page_select":
            what = quoted.map { "is choosing in \($0)" } ?? "is choosing an option\(on)"
        case "page_scroll":
            what = site.map { "is scrolling \($0)" } ?? "is scrolling"
        case "page_drag":
            what = quoted.map { "is dragging \($0)" } ?? "is dragging\(on)"
        case "page_upload":
            what = site.map { "is uploading a file to \($0)" } ?? "is uploading a file"
        case "page_navigate", "tab_open":
            let host = (arguments["url"] as? String).flatMap(Self.site)
            what = host.map { "is opening \($0)" } ?? "is opening a page"
        case "page_history":
            switch arguments["action"] as? String {
            case "back": what = "is going back"
            case "forward": what = "is going forward"
            default: what = site.map { "is reloading \($0)" } ?? "is reloading the page"
            }
        case "tab_close": what = "is closing a tab"
        case "page_evaluate": what = site.map { "is running a script on \($0)" } ?? "is running a script"
        case "page_download": what = site.map { "is downloading from \($0)" } ?? "is downloading a file"
        case "download_cancel": what = "is cancelling a download"
        case "page_pdf": what = site.map { "is saving \($0) as a PDF" } ?? "is saving a PDF"
        default: what = "is using Cra"
        }
        return "\(agent) \(what)"
    }

    /// A key as the Mac writes it: ⌃⌥⇧⌘ before the key, a letter in capitals (⌘K, ⇧Tab, Enter).
    static func keys(_ key: String, modifiers: String?) -> String? {
        guard !key.isEmpty, key.count <= 12, !key.contains(where: { $0.isNewline }) else { return nil }
        let names = Set((modifiers ?? "").split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let glyphs = [("control", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("meta", "⌘")].filter { names.contains($0.0) }.map(\.1).joined()
        return glyphs + (key.count == 1 ? key.uppercased() : key)
    }

    /// ⌘. takes over from an agent while its pill is up: the period key (ANSI key code 47, which
    /// types "." on Danish and US layouts alike) or whichever key types "." with ⌘ alone. ⇧⌘. and
    /// the rest are left to their own shortcuts.
    public static func isTakeOverKey(keyCode: UInt16, characters: String?, command: Bool, shift: Bool, option: Bool, control: Bool) -> Bool {
        command && !shift && !option && !control && (keyCode == 47 || characters == ".")
    }

    /// A host without its `www.`, for the toast (nil for anything that isn't a web address).
    public static func site(_ url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Page text in Cra's toast: one line, in quotes, cut at `targetLimit`; nil when nothing is left.
    static func quote(_ text: String) -> String? {
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) }
        let words = String(String.UnicodeScalarView(line)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        let cut = words.count > targetLimit ? String(words.prefix(targetLimit - 1)).trimmingCharacters(in: .whitespaces) + "…" : words
        return "“\(cut)”"
    }

    /// The pointer's way to a target while the user watches the tab: long enough to follow with the
    /// eye (0.3 s across a button, 0.6 s across the page), against the 0.06–0.24 s an unwatched
    /// pointer takes. A target where the pointer already is needs no glide.
    public static func watchedGlide(from start: CGPoint, to end: CGPoint, variation: Double) -> [MCPInputPlan.Move] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance >= 2 else { return [MCPInputPlan.Move(point: end, delay: 0)] }
        return MCPInputPlan.movement(from: start, to: end, variation: variation, duration: glideDuration(distance: distance))
    }

    public static func glideDuration(distance: Double) -> Double { min(0.6, max(0.3, 0.22 + distance / 2200)) }

    /// Where the face's eyes look, as an offset of at most `reach` from their rest: along the way
    /// the face travels (y down, as on the page), straight ahead when it stands still.
    public static func gaze(dx: Double, dy: Double, reach: Double) -> CGVector {
        let length = hypot(dx, dy)
        guard length >= 0.5, reach > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / length * reach, dy: dy / length * reach)
    }
}
