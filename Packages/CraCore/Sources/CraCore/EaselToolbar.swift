import CoreGraphics
import Foundation

extension Easel.Tool {
    /// The key that picks the tool while the canvas has the keyboard (Arc 1.173.1, 17 Nov 2026:
    /// the letters Arc draws in the buttons; R, O and V were pressed and picked the rectangle,
    /// the ellipse and the pointer).
    public var key: Character {
        switch self {
        case .pointer: "v"
        case .image: "i"
        case .text: "t"
        case .ellipse: "o"
        case .rectangle: "r"
        case .arrow: "a"
        case .freehand: "p"
        }
    }

    /// The letter in the button's corner while the pointer is over it or the tool is picked.
    /// Arc's pointer button shows none.
    public var keyHint: String? { self == .pointer ? nil : String(key) }

    /// The tool a key press picks: its letter alone, in either case. With ⌘, ⌃ or ⌥ the press is
    /// a shortcut or another character, not a tool.
    public static func picked(byKey characters: String, command: Bool = false, control: Bool = false, option: Bool = false) -> Easel.Tool? {
        guard !command, !control, !option, characters.count == 1, let c = characters.lowercased().first else { return nil }
        return allCases.first { $0.key == c }
    }
}

/// Arc's Easel toolbar in its own coordinates (points, y down), measured on Arc 1.173.1 at 2x
/// (17 Nov 2026): a 44 pt bar of 36 pt buttons 38 pt apart, 4 pt in; after the last tool a 5 pt
/// gap with a 1 pt line in its middle, then Duplicate.
public enum EaselToolbarLayout {
    public enum Item: Equatable, Sendable {
        case tool(Easel.Tool)
        case duplicate
    }

    /// A button's backing: nothing, the pointer over it, or the picked tool.
    public enum Fill: Equatable, Sendable { case none, hovered, picked }

    public struct Look: Equatable, Sendable {
        public var fill: Fill
        /// The key letter in the corner, if it shows.
        public var hint: String?
        public init(fill: Fill, hint: String?) { (self.fill, self.hint) = (fill, hint) }
    }

    public static let height: CGFloat = 44
    public static let inset: CGFloat = 4
    public static let button: CGFloat = 36
    public static let pitch: CGFloat = 38
    public static let dividerGap: CGFloat = 5
    /// The letter: 10 pt bold, its right edge this far inside the button's and its baseline this
    /// far above the button's bottom.
    public static let hintSize: CGFloat = 10
    public static let hintTrailing: CGFloat = 5.5
    public static let hintBaseline: CGFloat = 4.2

    public static var items: [Item] { Easel.Tool.allCases.map(Item.tool) + [.duplicate] }

    private static var toolsEnd: CGFloat { inset + CGFloat(Easel.Tool.allCases.count - 1) * pitch + button }

    public static func rect(of item: Item) -> CGRect {
        switch item {
        case .tool(let tool):
            let i = Easel.Tool.allCases.firstIndex(of: tool) ?? 0
            return CGRect(x: inset + CGFloat(i) * pitch, y: inset, width: button, height: button)
        case .duplicate:
            return CGRect(x: toolsEnd + dividerGap, y: inset, width: button, height: button)
        }
    }

    /// The line between the tools and Duplicate.
    public static var divider: CGRect {
        CGRect(x: toolsEnd + (dividerGap - 1) / 2, y: inset, width: 1, height: button)
    }

    public static var width: CGFloat { rect(of: .duplicate).maxX + inset }

    public static func item(at point: CGPoint) -> Item? {
        items.first { rect(of: $0).contains(point) }
    }

    /// What a button shows. The picked tool keeps its fill whatever the pointer does; another
    /// button under the pointer gets the hover fill. A tool's letter shows while it is picked or
    /// under the pointer; Duplicate has none.
    public static func look(of item: Item, picked: Easel.Tool, hovered: Item?) -> Look {
        switch item {
        case .tool(let tool):
            let isPicked = tool == picked, isHovered = hovered == item
            return Look(fill: isPicked ? .picked : isHovered ? .hovered : .none,
                        hint: isPicked || isHovered ? tool.keyHint : nil)
        case .duplicate:
            return Look(fill: hovered == item ? .hovered : .none, hint: nil)
        }
    }
}
