import Foundation
import CoreGraphics

/// Human pacing is data, so bounds and endpoints can be tested without a real clock.
public enum MCPInputPlan {
    public struct Move {
        public let point: CGPoint
        public let delay: Double
    }

    public static func movement(from start: CGPoint, to end: CGPoint, variation: Double) -> [Move] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = min(0.65, 0.16 + distance / 1800)
        let steps = max(8, Int(duration / 0.016))
        let bend = (min(1, max(0, variation)) - 0.5) * min(70, distance * 0.2)
        let length = max(1, distance)
        let control = CGPoint(x: (start.x + end.x) / 2 - (end.y - start.y) / length * bend,
                              y: (start.y + end.y) / 2 + (end.x - start.x) / length * bend)
        return (1...steps).map { index in
            let fraction = Double(index) / Double(steps)
            let t = fraction * fraction * (3 - 2 * fraction)
            let u = 1 - t
            return Move(point: CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y),
                        delay: duration / Double(steps))
        }
    }

    public static func keyHold(_ variation: Double) -> Double { 0.025 + bounded(variation) * 0.035 }
    public static func keyGap(_ variation: Double) -> Double { 0.035 + bounded(variation) * 0.060 }
    public static func clickHold(_ variation: Double) -> Double { 0.055 + bounded(variation) * 0.055 }
    private static func bounded(_ value: Double) -> Double { min(1, max(0, value)) }

    public static let keys: [String: (code: String, virtual: Int)] = [
        "Enter": ("Enter", 13), "Tab": ("Tab", 9), "Backspace": ("Backspace", 8),
        "Delete": ("Delete", 46), "Escape": ("Escape", 27),
        "ArrowLeft": ("ArrowLeft", 37), "ArrowUp": ("ArrowUp", 38),
        "ArrowRight": ("ArrowRight", 39), "ArrowDown": ("ArrowDown", 40),
        "Home": ("Home", 36), "End": ("End", 35),
        "PageUp": ("PageUp", 33), "PageDown": ("PageDown", 34)
    ]

    public struct TextKey {
        public let code: String
        public let virtual: Int
        public let modifiers: Int
        public let unmodified: String
    }

    /// CDP's text handles Unicode; ASCII additionally gets the usual physical key identity.
    public static func textKey(_ character: Character) -> TextKey? {
        let text = String(character)
        guard let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1, scalar.isASCII else { return nil }
        if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) {
            return TextKey(code: "Key" + text.uppercased(), virtual: Int(text.uppercased().utf8.first!),
                           modifiers: (65...90).contains(scalar.value) ? 8 : 0, unmodified: text.lowercased())
        }
        if (48...57).contains(scalar.value) { return TextKey(code: "Digit" + text, virtual: Int(scalar.value), modifiers: 0, unmodified: text) }
        let punctuation: [(String, String, String, Int)] = [
            (" ", " ", "Space", 32), ("-", "_", "Minus", 189), ("=", "+", "Equal", 187),
            ("[", "{", "BracketLeft", 219), ("]", "}", "BracketRight", 221),
            (";", ":", "Semicolon", 186), ("'", "\"", "Quote", 222),
            (",", "<", "Comma", 188), (".", ">", "Period", 190), ("/", "?", "Slash", 191),
            ("`", "~", "Backquote", 192), ("\\", "|", "Backslash", 220)
        ]
        for (plain, shifted, code, virtual) in punctuation where text == plain || text == shifted {
            return TextKey(code: code, virtual: virtual, modifiers: text == plain ? 0 : 8, unmodified: plain)
        }
        let shifted = Array(")!@#$%^&*(")
        if let digit = shifted.firstIndex(of: character) {
            return TextKey(code: "Digit\(digit)", virtual: 48 + digit, modifiers: 8, unmodified: String(digit))
        }
        return nil
    }

    /// Blink reserves a terminator in its four-unit buffer: at most three UTF-16 units per event. A longer grapheme (a ZWJ family,
    /// a stack of combining marks) is typed as several events cut between scalars, never inside a surrogate pair.
    public static let pieceUTF16Limit = 3
    public static let pieceLimit = 256

    public static func textPieces(_ text: String) -> [String] {
        var pieces: [String] = []
        for character in text {
            let whole = String(character)
            if whole.utf16.count <= pieceUTF16Limit { pieces.append(whole); continue }
            var piece = String.UnicodeScalarView()
            var units = 0
            for scalar in character.unicodeScalars {
                let width = UTF16.width(scalar)
                if units + width > pieceUTF16Limit {
                    pieces.append(String(piece))
                    piece = String.UnicodeScalarView()
                    units = 0
                }
                piece.append(scalar)
                units += width
            }
            if !piece.isEmpty { pieces.append(String(piece)) }
        }
        return pieces
    }

    /// Each piece pauses at most keyHold(1) + keyGap(1) ≈ 0.155 s and makes a caret check and two key
    /// dispatches; ~0.215 s per piece plus a 45 s base for clicking, clearing and verifying leaves room for both.
    public static func durationBudget(text: String) -> Double {
        min(100, 45 + Double(textPieces(text).count) * 55 / Double(pieceLimit))
    }

    public static func validText(_ text: String) -> Bool {
        text.count <= 256 && text.utf8.count <= 4096
            && !text.unicodeScalars.contains { $0.value < 32 && $0.value != 10 || $0.value == 127 }
            && textPieces(text).count <= pieceLimit
    }
}
