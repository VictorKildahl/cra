import Foundation

/// A space's icon: an emoji, an SF Symbol from the Icon tab of Arc's picker, a picture the user
/// chose, or none (Remove Icon). sidebar.json keeps it as `emoji`, `symbol` and `iconImage`, never
/// more than one: a symbol or picture leaves `emoji` empty.
public enum SpaceIcon: Hashable, Sendable {
    case emoji(String)
    case symbol(String)
    /// PNG bytes of a user-chosen picture, scaled small by the app.
    case image(Data)
    case none

    /// What New Space starts with.
    public static let newSpace = SpaceIcon.emoji("🌱")

    /// The stored fields: a picture wins over a symbol, and a symbol over an emoji beside it.
    public init(emoji: String, symbol: String?, image: Data? = nil) {
        if let image, !image.isEmpty { self = .image(image) }
        else if let symbol, !symbol.isEmpty { self = .symbol(symbol) } else if emoji.isEmpty { self = .none } else { self = .emoji(emoji) }
    }

    /// `Space.emoji`: empty for a symbol, a picture or no icon.
    public var emoji: String {
        if case .emoji(let e) = self { return e }
        return ""
    }

    /// `Space.symbol`.
    public var symbol: String? {
        if case .symbol(let s) = self { return s }
        return nil
    }

    /// `Space.iconImage`.
    public var image: Data? {
        if case .image(let d) = self { return d }
        return nil
    }
}

extension Space {
    /// Reading and writing both fields at once, so an emoji and a symbol never stack (#205).
    public var icon: SpaceIcon {
        get { SpaceIcon(emoji: emoji, symbol: symbol, image: iconImage) }
        set {
            emoji = newValue.emoji
            symbol = newValue.symbol
            iconImage = newValue.image
        }
    }

    /// The name as a menu lists it: the emoji first when there is one, so a space with a symbol,
    /// a picture or no icon (a dot in the dock) has no gap in front of its name.
    public var labeled: String { emoji.isEmpty ? title : "\(emoji) \(title)" }
}
