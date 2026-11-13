import Foundation

/// Which file input page_upload selects files in, for the element an agent pointed at.
///
/// Sites hide the input and show a button, label or drop zone instead, and components keep the
/// input inside open shadow roots, where page_snapshot has no ref for it and a CSS selector
/// can't reach it (reddit.com's community and profile image uploaders, 12 Nov 2026). So the
/// target may be the input itself, a label for it, an element holding exactly one, or an
/// element of a shadow component that holds exactly one. Plain-DOM neighbours don't count: a
/// text field next to a form's file input is still refused, and an input it can't tell apart
/// from another is never guessed.
public enum MCPUploadTarget {
    /// What MCPInput's inspection saw around the target.
    public struct Surroundings: Equatable, Sendable {
        /// The target is an `<input type=file>`.
        public var isFileInput: Bool
        /// The target is, or is inside, a `<label>` whose control is a file input.
        public var labelsFileInput: Bool
        /// The target is another form field, or labels one: never an uploader.
        public var isOtherField: Bool
        /// File inputs inside the target, through open shadow roots.
        public var inside: Int
        /// File inputs in each shadow component around the target, nearest first: the shadow
        /// root it is in, or the host it is slotted into, then the ones around that, up to the
        /// document (which isn't one).
        public var components: [Int]

        public init(isFileInput: Bool = false, labelsFileInput: Bool = false, isOtherField: Bool = false,
                    inside: Int = 0, components: [Int] = []) {
            self.isFileInput = isFileInput
            self.labelsFileInput = labelsFileInput
            self.isOtherField = isOtherField
            self.inside = inside
            self.components = components
        }
    }

    public enum Choice: Equatable, Sendable {
        /// The target is the file input.
        case itself
        /// The file input the target's label is for.
        case label
        /// The one file input inside the target.
        case inside
        /// The one file input of the nth component around the target (an index of `components`).
        case component(Int)
        /// No input, or more than one: the message says what to pass instead.
        case refused(String)

        /// How the input was reached, for page_upload's result; nil when the target was the input.
        public var via: String? {
            switch self {
            case .label: "label"
            case .inside: "inside"
            case .component: "component"
            case .itself, .refused: nil
            }
        }
    }

    public static func choose(_ around: Surroundings) -> Choice {
        if around.isFileInput { return .itself }
        if around.labelsFileInput { return .label }
        if around.isOtherField {
            return .refused("That is a form field, not a file input. Pass the file input, or the button, label or drop zone of its uploader.")
        }
        if around.inside == 1 { return .inside }
        if around.inside > 1 {
            return .refused("\(around.inside) file inputs are inside this element. Pass one of them, or the button, label or drop zone of one uploader.")
        }
        if let nearest = around.components.firstIndex(where: { $0 > 0 }) {
            if around.components[nearest] == 1 { return .component(nearest) }
            return .refused("This element's component holds \(around.components[nearest]) file inputs, so which one is meant can't be told. Pass a label of one, or a ref or selector inside one uploader.")
        }
        return .refused("No file input belongs to this element. Pass the file input, or the button, label or drop zone of its uploader (it may sit in the same shadow-root component).")
    }
}
