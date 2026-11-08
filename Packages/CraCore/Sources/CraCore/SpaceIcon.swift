import Foundation

/// A space's icon: an emoji, an SF Symbol from the Icon tab of Arc's picker, or none (Remove
/// Icon). sidebar.json keeps it as `emoji` and `symbol`, never both: a symbol leaves `emoji` empty.
public enum SpaceIcon: Hashable, Sendable {
    case emoji(String)
    case symbol(String)
    case none

    /// What New Space starts with.
    public static let newSpace = SpaceIcon.emoji("🌱")

    /// The stored pair: a symbol wins over an emoji beside it.
    public init(emoji: String, symbol: String?) {
        if let symbol, !symbol.isEmpty { self = .symbol(symbol) } else if emoji.isEmpty { self = .none } else { self = .emoji(emoji) }
    }

    /// `Space.emoji`: empty for a symbol or no icon.
    public var emoji: String {
        if case .emoji(let e) = self { return e }
        return ""
    }

    /// `Space.symbol`.
    public var symbol: String? {
        if case .symbol(let s) = self { return s }
        return nil
    }
}

extension Space {
    /// Reading and writing both fields at once, so an emoji and a symbol never stack (#205).
    public var icon: SpaceIcon {
        get { SpaceIcon(emoji: emoji, symbol: symbol) }
        set {
            emoji = newValue.emoji
            symbol = newValue.symbol
        }
    }

    /// The name as a menu lists it: the emoji first when there is one, so a space with a symbol
    /// or no icon (a dot in the dock) has no gap in front of its name.
    public var labeled: String { emoji.isEmpty ? title : "\(emoji) \(title)" }
}
