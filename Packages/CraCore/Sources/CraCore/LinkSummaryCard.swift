import CoreGraphics
import Foundation

/// A card's content.
public struct LinkSummaryResult: Equatable, Sendable {
    public struct Detail: Equatable, Sendable {
        /// Arc's examples: "Price", "Story", "Solution 1", "Highlights", "Criticism".
        public var label: String
        /// An SF Symbol name the model chose; the card falls back when the system has no such symbol.
        public var icon: String
        public var info: String

        public init(label: String, icon: String, info: String) {
            self.label = label
            self.icon = icon
            self.info = info
        }
    }

    public var url: String
    public var title: String
    public var host: String
    public var quickSummary: String?
    public var details: [Detail]

    public init(url: String, title: String, host: String, quickSummary: String?, details: [Detail]) {
        self.url = url
        self.title = title
        self.host = host
        self.quickSummary = quickSummary
        self.details = details
    }
}

/// The card's size and place, measured on Arc 1.171 (10 Nov 2026, a Hacker News story on a 2x
/// display): 300 pt wide, a 100 pt banner, 15 pt margins, rows indented to 39 pt, 6 pt between
/// rows, 12 pt corners. It hangs 6 pt under the link, 7 pt left of the link's start.
public enum LinkSummaryCardLayout {
    public static let width: CGFloat = 300
    public static let bannerHeight: CGFloat = 100
    public static let cornerRadius: CGFloat = 12
    public static let margin: CGFloat = 15
    public static let rowIndent: CGFloat = 39
    public static let rowGap: CGFloat = 6
    public static let lineHeight: CGFloat = 18.5
    /// Room under the last row for the share button (32 pt, its centre 24 pt from the right and
    /// 25 pt from the bottom).
    public static let bottomInset: CGFloat = 40
    public static let shareButton: CGFloat = 32
    /// The loading card: two grey bars 7 pt thick, 15 pt apart, in a card 52 pt tall.
    public static let loadingHeight: CGFloat = 52
    public static let barThickness: CGFloat = 7
    public static let barPitch: CGFloat = 15
    /// The small card: the title in bold on 16 pt lines (two at most), 10 pt above the address.
    public static let titleLineHeight: CGFloat = 16
    public static let addressGap: CGFloat = 10
    /// Opening grows the card down from its top edge in 0.25 s; closing squashes it
    /// toward its top edge to about a third, fading out, in 0.14 s (60 fps recordings).
    public static let openDuration: Double = 0.25
    /// It is opaque by its second or third frame while it keeps growing.
    public static let openFade: Double = 0.06
    public static let closeDuration: Double = 0.14
    public static let closeScale: CGFloat = 0.3
    static let gapBelowLink: CGFloat = 6
    static let leadBeforeLink: CGFloat = 7

    /// Where the card goes, in screen coordinates (y up). Under the link when it fits on the
    /// screen, else above it; without the link's frame, under the pointer. Kept 8 pt inside the screen.
    public static func origin(size: CGSize, link: CGRect?, pointer: CGPoint, screen: CGRect) -> CGPoint {
        let anchor = link ?? CGRect(x: pointer.x - 20, y: pointer.y - 10, width: 40, height: 20)
        var x = anchor.minX - leadBeforeLink
        var y = anchor.minY - gapBelowLink - size.height
        if y < screen.minY + 8 { y = anchor.maxY + gapBelowLink }
        x = min(max(x, screen.minX + 8), screen.maxX - 8 - size.width)
        y = min(max(y, screen.minY + 8), screen.maxY - 8 - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

/// The share button's menu (Arc: Copy as Text, Copy as Image, Share).
public enum LinkSummaryShare {
    /// Copy as Text, line for line as Arc copies it: the quick summary, a line per detail led by
    /// its symbol's emoji, the attribution, the link.
    public static func text(_ r: LinkSummaryResult, attribution: String) -> String {
        var lines: [String] = []
        if let q = r.quickSummary { lines.append(q) }
        for d in r.details {
            let lead = emoji(forSymbol: d.icon)
            lines.append(d.label.isEmpty ? "\(lead) \(d.info)" : "\(lead) \(d.label): \(d.info)")
        }
        lines.append(attribution)
        lines.append(r.url)
        return lines.joined(separator: "\n")
    }

    /// The emoji for an SF Symbol name. Arc's table isn't readable; this one gives the four Arc
    /// produced (trophy 🏆, video 📹, pencil ✏️, paperplane ✈️) and the common symbols the model
    /// picks, by the name's first part. Unknown names get a bullet.
    public static func emoji(forSymbol name: String) -> String {
        let parts = name.lowercased().split(separator: ".").map(String.init)
        for k in stride(from: parts.count, through: 1, by: -1) {
            let key = parts.prefix(k).joined(separator: ".")
            if let e = wholeNames[key] ?? stems[key] { return e }
        }
        return "•"
    }

    static let wholeNames: [String: String] = [
        "fork.knife": "🍴", "cup.and.saucer": "☕️", "birthday.cake": "🎂", "flag.checkered": "🏁",
        "hand.thumbsup": "👍", "hand.thumbsdown": "👎", "chart.line.uptrend.xyaxis": "📈", "chart.line.downtrend.xyaxis": "📉",
        "exclamationmark.triangle": "⚠️", "person.2": "👥", "person.3": "👥", "globe.americas": "🌎", "globe.europe.africa": "🌍",
        "globe.asia.australia": "🌏", "music.note": "🎵", "play.rectangle": "▶️", "dollarsign.circle": "💲",
    ]

    static let stems: [String: String] = [
        "trophy": "🏆", "video": "📹", "pencil": "✏️", "paperplane": "✈️", "airplane": "✈️", "star": "⭐️", "heart": "❤️",
        "cart": "🛒", "bag": "🛍️", "dollarsign": "💲", "banknote": "💵", "creditcard": "💳", "tag": "🏷️", "calendar": "📅",
        "clock": "🕒", "alarm": "⏰", "timer": "⏱️", "hourglass": "⌛️", "book": "📖", "books": "📚", "doc": "📄",
        "newspaper": "📰", "globe": "🌐", "map": "🗺️", "mappin": "📍", "location": "📍", "person": "👤", "figure": "🏃",
        "house": "🏠", "building": "🏢", "building.2": "🏢", "car": "🚗", "bus": "🚌", "tram": "🚋", "bicycle": "🚲",
        "ferry": "⛴️", "truck": "🚚", "shippingbox": "📦", "lightbulb": "💡", "chart": "📊", "gear": "⚙️",
        "gearshape": "⚙️", "wrench": "🔧", "hammer": "🔨", "lock": "🔒", "key": "🔑", "checkmark": "✅", "xmark": "❌",
        "info": "ℹ️", "questionmark": "❓", "exclamationmark": "❗️", "flag": "🚩", "bolt": "⚡️", "leaf": "🍃",
        "flame": "🔥", "sun": "☀️", "moon": "🌙", "cloud": "☁️", "snowflake": "❄️", "drop": "💧", "umbrella": "☂️",
        "thermometer": "🌡️", "wind": "💨", "music": "🎵", "photo": "🖼️", "camera": "📷", "iphone": "📱", "phone": "📞",
        "envelope": "✉️", "bubble": "💬", "link": "🔗", "gift": "🎁", "graduationcap": "🎓", "briefcase": "💼",
        "laptopcomputer": "💻", "desktopcomputer": "🖥️", "cpu": "💻", "gamecontroller": "🎮", "sportscourt": "🏟️",
        "pills": "💊", "cross": "➕", "stethoscope": "🩺", "ticket": "🎟️", "film": "🎬", "tv": "📺", "mic": "🎤",
        "speaker": "🔊", "battery": "🔋", "shield": "🛡️", "magnifyingglass": "🔍", "sparkles": "✨", "sparkle": "✨",
        "list": "📝", "text": "📝", "megaphone": "📣", "crown": "👑", "medal": "🏅", "rosette": "🏵️", "eye": "👁️",
        "brain": "🧠", "puzzlepiece": "🧩", "paintbrush": "🖌️", "paintpalette": "🎨", "scissors": "✂️", "ruler": "📏",
        "folder": "📁", "tray": "📥", "archivebox": "🗃️", "bookmark": "🔖", "paperclip": "📎", "pin": "📌",
        "pawprint": "🐾", "tortoise": "🐢", "hare": "🐇", "fish": "🐟", "bird": "🐦", "ant": "🐜", "ladybug": "🐞",
        "carrot": "🥕", "wineglass": "🍷", "fuelpump": "⛽️", "arrow": "➡️", "play": "▶️", "hand": "✋", "hands": "🙌",
    ]
}
