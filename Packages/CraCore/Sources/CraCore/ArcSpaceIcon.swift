import Foundation

/// An Arc space's icon, read from `customInfo.iconType` in Arc's StorableSidebar.json. Arc's
/// `IconType` has four cases: `emoji_v2` (a string, written beside the older numeric `emoji`), `icon`
/// (a name from the Icon tab of its picker, `SymbolIconType`, e.g. `{"icon": "star"}`) and `symbol`.
public enum ArcSpaceIcon {
    /// What an icon Cra can't read becomes: a space that had an icon keeps one (#252).
    public static let fallback = "🗂️"

    /// Arc's Icon tab in its order (7 rows of 8), each beside the SF Symbol Cra's Icon tab shows in
    /// the same slot. Arc's planet, pizza and skull have no SF Symbol and get the nearest one.
    public static let picker: [(arc: String, symbol: String)] = [
        ("star", "star.fill"), ("bookmark", "bookmark.fill"), ("heart", "heart.fill"), ("flag", "flag.fill"),
        ("flash", "bolt.fill"), ("triangle", "triangle.fill"), ("medical", "asterisk"), ("notifications", "bell.fill"),
        ("bulb", "lightbulb.fill"), ("shapes", "triangle.circle.fill"), ("grid", "square.grid.2x2.fill"),
        ("apps", "circle.grid.3x3.fill"), ("layers", "square.stack.3d.up.fill"), ("server", "cylinder.split.1x2.fill"),
        ("albums", "archivebox.fill"), ("copy", "square.on.square.fill"),
        ("folder", "folder.fill"), ("fileTrayFull", "tray.full.fill"), ("calendar", "calendar"), ("mail", "envelope.fill"),
        ("checkbox", "checkmark.square.fill"), ("document", "doc.fill"), ("book", "book.fill"),
        ("chatBubbleEllipses", "ellipsis.bubble.fill"),
        ("people", "person.2.fill"), ("terminal", "apple.terminal.fill"), ("construction", "wrench.and.screwdriver.fill"),
        ("square", "square.fill"), ("egg", "oval.portrait.fill"), ("ellipse", "circle.fill"), ("moon", "moon.fill"),
        ("sunny", "sun.max.fill"),
        ("planet", "globe.americas.fill"), ("leaf", "leaf.fill"), ("cloud", "cloud.fill"), ("paw", "pawprint.fill"),
        ("bag", "basket.fill"), ("gift", "gift.fill"), ("bed", "bed.double.fill"), ("restaurant", "fork.knife"),
        ("barbell", "dumbbell.fill"), ("airplane", "airplane"), ("musicalNote", "music.note"),
        ("colorPallete", "paintpalette.fill"), ("video", "video.fill"), ("bandage", "bandage.fill"),
        ("code", "chevron.left.forwardslash.chevron.right"), ("baseball", "baseball.fill"),
        ("cloudOutline", "cloud"), ("map", "map.fill"), ("bonfire", "flame.fill"), ("pizza", "birthday.cake.fill"),
        ("skull", "theatermasks.fill"), ("receipt", "scroll.fill"), ("thumbsUp", "hand.thumbsup.fill"), ("train", "tram.fill"),
    ]

    /// `SymbolIconType` names past the picker's 56. Arc's github, linear and figma are brand marks
    /// with no SF Symbol, so they are left to `fallback`.
    static let extra = ["rss": "dot.radiowaves.up.forward", "search": "magnifyingglass"]

    /// The SF Symbol for an Arc Icon-tab name, nil when Cra has none.
    public static func symbol(forArcIcon name: String) -> String? {
        picker.first { $0.arc == name }?.symbol ?? extra[name]
    }

    /// The icon of an Arc space with this `iconType`. No `iconType` is Remove Icon in Arc, a dot in
    /// its dock, and stays icon-less (#252). `symbolExists` says whether macOS has an SF Symbol of
    /// that name, for Arc's `symbol` case, which names one directly.
    public static func icon(_ iconType: [String: Any]?, symbolExists: (String) -> Bool) -> SpaceIcon {
        guard let iconType else { return .none }
        if let e = iconType["emoji_v2"] as? String { return SpaceIcon(emoji: e, symbol: nil) }
        if let code = iconType["emoji"] as? Int, let scalar = UnicodeScalar(code) { return .emoji(String(Character(scalar))) }
        if let name = iconType["icon"] as? String, let symbol = symbol(forArcIcon: name) { return .symbol(symbol) }
        if let name = iconType["symbol"] as? String, !name.isEmpty, symbolExists(name) { return .symbol(name) }
        return .emoji(fallback)
    }
}

extension SpaceIcon {
    /// The Icon tab of Cra's picker: Arc's 56 glyphs first, then Cra's own extras.
    public static let pickerSymbols = ArcSpaceIcon.picker.map(\.symbol) + extraPickerSymbols

    /// Extra Icon-tab glyphs past Arc's 56.
    public static let extraPickerSymbols: [String] = [
        "house.fill", "building.2.fill", "briefcase.fill", "graduationcap.fill",
        "cart.fill", "creditcard.fill", "lock.fill", "key.fill",
        "wifi", "antenna.radiowaves.left.and.right", "desktopcomputer", "laptopcomputer",
        "iphone", "headphones", "camera.fill", "photo.fill",
        "mic.fill", "speaker.wave.2.fill", "tv.fill", "gamecontroller.fill",
        "car.fill", "bicycle", "bus.fill", "ferry.fill",
        "figure.walk", "figure.run", "cup.and.saucer.fill", "drop.fill",
        "snowflake", "umbrella.fill", "tree.fill", "mountain.2.fill",
        "tent.fill", "binoculars.fill", "location.fill", "tag.fill",
        "link", "paperplane.fill", "printer.fill", "scissors",
        "pencil", "paintbrush.pointed.fill", "sparkles", "crown.fill",
        "trophy.fill", "medal.fill", "target", "puzzlepiece.fill",
        "chart.bar.fill", "clock.fill", "hourglass", "magnifyingglass",
        "newspaper.fill", "hammer.fill", "stethoscope", "cross.case.fill",
        "pill.fill", "flask.fill", "atom", "cat.fill",
        "dog.fill", "fish.fill", "bird.fill", "tortoise.fill",
    ]
}
