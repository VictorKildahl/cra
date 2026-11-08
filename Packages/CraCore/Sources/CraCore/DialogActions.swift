import Foundation

public struct DialogAction: Equatable, Sendable {
    public enum Role: Sendable { case primary, secondary, destructive, cancel }

    public let title: String
    public let role: Role

    public init(_ title: String, role: Role = .primary) {
        self.title = title
        self.role = role
    }

    public static let cancel = DialogAction("Cancel", role: .cancel)
}

public struct DialogActions: Equatable, Sendable {
    public let buttons: [DialogAction]

    public init(_ buttons: [DialogAction]) {
        precondition(!buttons.isEmpty, "A dialog needs at least one button")
        self.buttons = buttons
    }

    public var defaultIndex: Int? {
        buttons.firstIndex { $0.role == .primary || $0.role == .destructive }
    }

    public var cancelIndex: Int? {
        buttons.firstIndex { $0.role == .cancel } ?? (buttons.count == 1 ? 0 : nil)
    }

    public var displayOrder: [Int] {
        let others = buttons.indices.reversed().filter { $0 != defaultIndex }
        return others + (defaultIndex.map { [$0] } ?? [])
    }

    /// Buttons at the card's left edge: secondary choices such as Arc's "Quit, and don’t ask again".
    public var leadingOrder: [Int] { displayOrder.filter { buttons[$0].role == .secondary } }

    /// Buttons at the card's right edge, the default last.
    public var trailingOrder: [Int] { displayOrder.filter { buttons[$0].role != .secondary } }

    public func key(at index: Int) -> String {
        if index == defaultIndex { return "↩" }
        return index == cancelIndex ? "ESC" : ""
    }

    public func isEnabled(at index: Int, input: String?, requiresInput: Bool) -> Bool {
        index != defaultIndex || !requiresInput || !(input ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
