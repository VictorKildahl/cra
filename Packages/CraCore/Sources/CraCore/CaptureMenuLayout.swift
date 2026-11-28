import CoreGraphics
import Foundation

/// Arc's menu beside a capture (Arc 1.173.1, a 2x still, 17 Nov 2026): a "Send To…" field on
/// top that takes the keyboard, then the capture's actions, Retake, and where it can go: New Easel
/// and every easel by name, picked straight from the menu. Edit, above Retake, opens Arc's image editor
/// (#851, CaptureEditorLayout). Arc's Save to Library row has no counterpart in Cra and is left out.
public enum CaptureMenuLayout {
    public enum Item: Equatable, Sendable {
        case copy, save, message, edit, retake, newEasel
        case easel(UUID)
    }

    public struct Row: Equatable, Sendable {
        public var item: Item
        public var title: String
        public init(_ item: Item, _ title: String) { (self.item, self.title) = (item, title) }
    }

    public struct Destination: Equatable, Sendable {
        public var id: UUID
        public var title: String
        public init(id: UUID, title: String) { (self.id, self.title) = (id, title) }
    }

    // Measured: 273 pt wide; the field 12 pt down, 30 pt tall, 10 pt in from both sides; the first
    // row 7.5 pt under it; 40 pt rows; sections 9 pt apart; 5.5 pt under the last row.
    public static let width: CGFloat = 273
    public static let fieldTop: CGFloat = 12
    public static let fieldHeight: CGFloat = 30
    public static let fieldInset: CGFloat = 10
    public static let fieldGap: CGFloat = 7.5
    public static let rowHeight: CGFloat = 40
    public static let sectionGap: CGFloat = 9
    public static let bottom: CGFloat = 5.5
    /// The easels listed at once, the latest edited first; typing in the field reaches the rest.
    public static let easelLimit = 8

    public static var header: CGFloat { fieldTop + fieldHeight + fieldGap }

    /// The rows to show, in Arc's order, for what is typed in the field: every row whose title
    /// holds the text, whatever its case; a section with none left goes with its line. With
    /// `maxHeight` (the page's height inside its margins) only the easels that fit are listed, so
    /// on a short page (a Peek, a Little Window) the menu's last rows don't run off it; typing
    /// still reaches the rest.
    public static func sections(easels: [Destination], filter: String = "", maxHeight: CGFloat = .infinity) -> [[Row]] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        func keep(_ rows: [Row]) -> [Row] { needle.isEmpty ? rows : rows.filter { $0.title.lowercased().contains(needle) } }
        let actions = keep([Row(.copy, "Copy"), Row(.save, "Save..."), Row(.message, "Send via iMessage...")])
        let again = keep([Row(.edit, "Edit"), Row(.retake, "Retake")])
        let named = easels.map { Row(.easel($0.id), $0.title.isEmpty ? "Untitled Easel" : $0.title) }
        let newEasel = keep([Row(.newEasel, "New Easel")])
        var listed = Array(keep(named).prefix(easelLimit))
        func all() -> [[Row]] { [actions, again, newEasel + listed].filter { !$0.isEmpty } }
        while !listed.isEmpty, height(all()) > maxHeight { listed.removeLast() }
        return all()
    }

    /// Whether the "Send To…" field, holding the keyboard, keeps a ⌘ key for its text (select all,
    /// paste, cut, undo and ⇧⌘Z redo) rather than the key ending the capture as other ⌘ keys do.
    public static func fieldKeeps(commandKey: String) -> Bool {
        ["a", "v", "x", "z"].contains(commandKey.lowercased())
    }

    public static func height(_ sections: [[Row]]) -> CGFloat {
        let rows = sections.reduce(0) { $0 + $1.count }
        return header + CGFloat(rows) * rowHeight + CGFloat(max(0, sections.count - 1)) * sectionGap + bottom
    }

    /// The row Return runs when none is picked: the first one shown, once something is typed.
    public static func defaultRow(_ sections: [[Row]], filter: String) -> Row? {
        filter.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sections.first?.first
    }
}

/// The capture menu's colours: ARC_Capture.bundle's named colours (Arc 1.174.3 Assets.car), each with a light value and
/// a dark one, so Arc's CapturedImageActionsView follows the Mac's appearance (#822; the 17 Nov measurement of the dark
/// menu ran in Dark mode). Background, TextColor, ButtonText (the glyphs, at Cra's measured 30 %), TextFieldBackground
/// and SeeMoreEaselTextColor (the field's prompt); the picked row is HoveredAndKeyboardSelectedBackground, the same blue in
/// both, under TextColorForSelectedCells. The dividers have no asset: white 7 % on the dark menu, black 7 % on the light.
public struct CaptureMenuTones: Equatable, Sendable {
    public struct Ink: Equatable, Sendable {
        public var rgb: RGB
        public var alpha: Double
        public init(_ rgb: RGB, _ alpha: Double = 1) { (self.rgb, self.alpha) = (rgb, alpha) }
    }

    public var fill: Ink
    /// Row titles and the field's typed text.
    public var text: Ink
    public var icon: Ink
    public var divider: Ink
    /// The "Send To…" field's box.
    public var field: Ink
    /// Its "Send To…" prompt.
    public var prompt: Ink
    /// The row the pointer or the arrow keys are on, and its title.
    public var hover: Ink
    public var hoverText: Ink

    /// `dark`: the Mac's appearance where the menu shows.
    public init(dark: Bool) {
        let ink: RGB = dark ? .white : .black
        fill = dark ? Ink(RGB(0.071, 0.059, 0.18)) : Ink(.white)
        text = Ink(ink, dark ? 0.9 : 1)
        icon = Ink(ink, 0.3)
        divider = Ink(ink, 0.07)
        field = Ink(ink, 0.07)
        prompt = Ink(ink, 0.45)
        hover = Ink(RGB(0.161, 0.18, 0.757))
        hoverText = Ink(.white, 0.95)
    }
}
