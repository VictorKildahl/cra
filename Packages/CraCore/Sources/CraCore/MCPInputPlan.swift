import Foundation
import CoreGraphics

/// Human pacing is data, so bounds and endpoints can be tested without a real clock.
public enum MCPInputPlan {
    public struct Move {
        public let point: CGPoint
        public let delay: Double
    }

    /// Short eased paths: pages that track the pointer (hover menus, drag thresholds) see real
    /// movement, without the second-long glides that made every click slow.
    public static func movement(from start: CGPoint, to end: CGPoint, variation: Double) -> [Move] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = min(0.24, 0.06 + distance / 4000)
        let steps = max(4, Int(duration / 0.016))
        let bend = (min(1, max(0, variation)) - 0.5) * min(40, distance * 0.1)
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

    public static func keyHold(_ variation: Double) -> Double { 0.008 + bounded(variation) * 0.017 }
    public static func keyGap(_ variation: Double) -> Double { 0.006 + bounded(variation) * 0.024 }
    public static func clickHold(_ variation: Double) -> Double { 0.030 + bounded(variation) * 0.040 }
    private static func bounded(_ value: Double) -> Double { min(1, max(0, value)) }

    public static let keys: [String: (code: String, virtual: Int)] = [
        "Enter": ("Enter", 13), "Tab": ("Tab", 9), "Backspace": ("Backspace", 8),
        "Delete": ("Delete", 46), "Escape": ("Escape", 27),
        "ArrowLeft": ("ArrowLeft", 37), "ArrowUp": ("ArrowUp", 38),
        "ArrowRight": ("ArrowRight", 39), "ArrowDown": ("ArrowDown", 40),
        "Home": ("Home", 36), "End": ("End", 35),
        "PageUp": ("PageUp", 33), "PageDown": ("PageDown", 34), "Space": ("Space", 32),
        "F1": ("F1", 112), "F2": ("F2", 113), "F3": ("F3", 114), "F4": ("F4", 115), "F5": ("F5", 116), "F6": ("F6", 117),
        "F7": ("F7", 118), "F8": ("F8", 119), "F9": ("F9", 120), "F10": ("F10", 121), "F11": ("F11", 122), "F12": ("F12", 123)
    ]

    /// page_press accepts a named key or one printable character ("k" with Meta is ⌘K).
    public static func pressable(_ key: String) -> Bool {
        if keys[key] != nil { return true }
        guard key.count == 1, let character = key.first else { return false }
        return !character.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } && textKey(character) != nil
    }

    /// Chromium on the Mac runs editing shortcuts as commands (NSResponder selectors), not from
    /// the key event alone, so ⌘A, ⌘Z or ⌥⌫ sent through DevTools need them spelled out.
    /// Modifier bits: Alt 1, Control 2, Meta 4, Shift 8.
    public static func editingCommands(key: String, modifiers: Int) -> [String] {
        let shift = modifiers & 8 != 0
        let select = shift ? "AndModifySelection" : ""
        switch (key.lowercased(), modifiers & ~8) {
        case ("a", 4): return shift ? [] : ["selectAll"]
        case ("c", 4): return shift ? [] : ["copy"]
        case ("x", 4): return shift ? [] : ["cut"]
        case ("v", 4): return shift ? [] : ["paste"]
        case ("v", 5): return shift ? ["pasteAndMatchStyle"] : []
        case ("z", 4): return [shift ? "redo" : "undo"]
        case ("arrowleft", 4): return ["moveToBeginningOfLine" + select]
        case ("arrowright", 4): return ["moveToEndOfLine" + select]
        case ("arrowup", 4): return ["moveToBeginningOfDocument" + select]
        case ("arrowdown", 4): return ["moveToEndOfDocument" + select]
        case ("arrowleft", 1): return ["moveWordLeft" + select]
        case ("arrowright", 1): return ["moveWordRight" + select]
        case ("backspace", 1): return shift ? [] : ["deleteWordBackward"]
        case ("delete", 1): return shift ? [] : ["deleteWordForward"]
        case ("backspace", 4): return shift ? [] : ["deleteToBeginningOfLine"]
        default: return []
        }
    }

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

    /// Text up to this many pieces is typed key by key (search boxes and autocompletes react to
    /// keys); longer text goes in as committed text (Input.insertText), like a paste or dictation.
    public static let keyTypingLimit = 100
    public static let textLimit = 20_000

    public static func typesKeys(_ text: String) -> Bool { textPieces(text).count <= keyTypingLimit }

    /// Each piece pauses at most keyHold(1) + keyGap(1) ≈ 0.055 s and makes a caret check and two
    /// key dispatches; a 45 s base covers clicking, clearing and verifying.
    public static func durationBudget(text: String) -> Double {
        typesKeys(text) ? min(100, 45 + Double(textPieces(text).count) * 0.25) : 60
    }

    public static func validText(_ text: String) -> Bool {
        text.count <= textLimit && text.utf8.count <= 100_000
            && !text.unicodeScalars.contains { $0.value < 32 && $0.value != 10 || $0.value == 127 }
    }
}
