import Foundation

/// What the link preview at the page's bottom left says about the link under the pointer, as in
/// Arc 1.17x (GitHub #689, the reporter's screenshots and recording of Arc): the address without
/// its scheme or a trailing slash ("adblock-tester.com/ad-blockers"), and while a key is held, what
/// a click will do: "Open <the whole address> in Peek" (⇧), "in Split View" (⌥) or "in a new tab"
/// (⌘), the address bright and the rest dim.
public enum LinkPreview {
    public enum Click: Equatable, Sendable {
        case peek, splitView, newTab
    }

    /// The preview's text: `emphasis` shows bright between the dim `lead` and `trail`.
    public struct Text: Equatable, Sendable {
        public var lead: String
        public var emphasis: String
        public var trail: String

        public init(lead: String, emphasis: String, trail: String) {
            self.lead = lead
            self.emphasis = emphasis
            self.trail = trail
        }

        public var string: String { lead + emphasis + trail }
    }

    private static let relevant: KeyChord.Modifiers = [.shift, .control, .option, .command]

    /// `status`: what the page reports for the link (its address). `modifiers`: the keys held now
    /// (AppKit's flags). `peekOnShiftClick`: Settings ▸ Links' Shift-click Peek, false in incognito,
    /// which has no Peek.
    public static func text(_ status: String, modifiers: UInt, peekOnShiftClick: Bool) -> Text {
        guard let click = click(status, modifiers: modifiers, peekOnShiftClick: peekOnShiftClick) else {
            return Text(lead: "", emphasis: "", trail: shortAddress(status))
        }
        let trail = switch click {
        case .peek: " in Peek"
        case .splitView: " in Split View"
        case .newTab: " in a new tab"
        }
        return Text(lead: "Open ", emphasis: status, trail: trail)
    }

    /// What a click on a link to `status` with these keys does in Cra, when it is one the preview
    /// names. ⇧ (also ⌥⇧) is a Peek (PeekTrigger), ⌥ and ⌘⌥ a split (LinkSplitClick), ⌘ and ⌘⇧ a
    /// tab. ⌃ makes any click a right-click. Web addresses only: a mail or script link opens in none.
    public static func click(_ status: String, modifiers: UInt, peekOnShiftClick: Bool) -> Click? {
        guard isWebAddress(status) else { return nil }
        let keys = KeyChord.Modifiers(rawValue: modifiers).intersection(relevant)
        if keys.contains(.control) { return nil }
        if keys == .option || keys == [.option, .command] { return .splitView }
        if keys.contains(.command) { return .newTab }
        if keys.contains(.shift) { return peekOnShiftClick ? .peek : nil }
        return nil
    }

    /// A web address without "https://" or "http://" and without the slash ending its path; anything
    /// else as it is.
    public static func shortAddress(_ status: String) -> String {
        guard isWebAddress(status), let colon = status.range(of: "://") else { return status }
        var rest = String(status[colon.upperBound...])
        if rest.hasSuffix("/"), !rest.contains("?"), !rest.contains("#") { rest.removeLast() }
        return rest
    }

    private static func isWebAddress(_ status: String) -> Bool {
        guard let url = URL(string: status), let scheme = url.scheme?.lowercased(), url.host?.isEmpty == false else { return false }
        return scheme == "http" || scheme == "https"
    }
}
