import Foundation

/// How big a text box on an Easel is, and what Return does in one (GitHub #580). Arc's easel text is
/// several lines that wrap inside the box (its export renders `white-space: pre-wrap`). Cra's box was
/// one line 240 pt wide whatever was typed: a longer text was cut off, and Return ended the typing.
/// Now the box widens with its longest line up to `textMaxWidth`, wraps past that, and grows down a
/// line at a time; Return starts a new line.
extension Easel {
    /// A new text box's width, and the narrowest one gets.
    public static let textMinWidth: Double = 240
    /// Past this a line wraps.
    public static let textMaxWidth: Double = 560
    /// Room the text field keeps around its text (its cell's insets and the caret).
    public static let textPadding: Double = 8

    /// One line of text at `size` points.
    public static func textLineHeight(size: Double) -> Double { (size * 1.45).rounded(.up) }

    /// The width for text whose longest line measures `longestLine` points unwrapped.
    public static func textWidth(longestLine: Double) -> Double {
        min(textMaxWidth, max(textMinWidth, (longestLine + textPadding).rounded(.up)))
    }

    /// The height for text at `size` points that takes `wrappedHeight` points laid out at its width;
    /// never less than one line.
    public static func textHeight(wrappedHeight: Double, size: Double) -> Double {
        max(textLineHeight(size: size), wrappedHeight.rounded(.up))
    }

    /// `frame` fitted to its text: the same top left, the width and height above.
    public static func fittedText(_ frame: Rect, longestLine: Double, size: Double, wrappedHeight: (Double) -> Double) -> Rect {
        let width = textWidth(longestLine: longestLine)
        return Rect(x: frame.x, y: frame.y, width: width, height: textHeight(wrappedHeight: wrappedHeight(width), size: size))
    }
}

/// What a key that ends a line does while a text box on an Easel is being typed in (#580).
public enum EaselTextKey: Equatable, Sendable {
    /// A new line in the text.
    case newline
    /// Typing ends and the box stays picked.
    case finish
    /// The text field handles it as usual.
    case pass

    /// From the text system's command (`insertNewline:`, `cancelOperation:`, …).
    public init(command: String) {
        switch command {
        case "insertNewline:", "insertLineBreak:", "insertNewlineIgnoringFieldEditor:": self = .newline
        case "cancelOperation:": self = .finish
        default: self = .pass
        }
    }
}
