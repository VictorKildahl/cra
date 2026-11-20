import Foundation

/// ⌥⌘V, Arc's "paste clipboard as new tab" (Arc 2023, gone from Arc in March 2024; kept in Cra by
/// Victor's call, #610): the copied link opens as a new tab, other text is searched. In a text field, a
/// page's or Cra's own, it pastes there, so a stray press never leaves what you write.
public enum PasteAndGo {
    public enum Outcome: Equatable, Sendable {
        /// Paste into the field that has the keys.
        case paste
        /// Open this text as a new tab (an address) or a search.
        case open(String)
        /// Nothing to open: the clipboard holds no text.
        case nothing
    }

    public static func outcome(typing: Bool, clipboard: String?) -> Outcome {
        if typing { return .paste }
        return line(clipboard).map(Outcome.open) ?? .nothing
    }

    /// The clipboard's text on one line, as the New Tab row's Paste and Go reads it: nil when there is
    /// none, or more than an address bar takes.
    public static func line(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty || line.count > 2048 ? nil : line
    }
}
