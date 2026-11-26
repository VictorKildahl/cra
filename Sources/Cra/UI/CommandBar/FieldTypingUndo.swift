import AppKit

/// ⌘Z and ⇧⌘Z for what the user typed in a field whose owner also writes into it (#809): the command bar's inline
/// completion and its arrowed-to rows replace the field's whole text, and each replacement emptied the field editor's
/// own undo history, so ⌘Z did nothing (Arc undoes the typing). Here the field editor keeps no history; each typed
/// change is registered with the window's undo manager instead, in steps as TypingUndoSteps groups them, and an undo
/// or redo hands the text back through `restore`, which puts it in the field as typed (no completion).
@MainActor
final class FieldTypingUndo: NSObject {
    private weak var field: NSTextField?
    private var steps = TypingUndoSteps()
    /// What the user has typed now, without a completion's rest: what a redo brings back.
    private var current = ""
    private let restore: (String) -> Void

    init(field: NSTextField, restore: @escaping (String) -> Void) {
        self.field = field
        self.restore = restore
    }

    private var undoManager: UndoManager? { field?.window?.undoManager }

    /// The field has its editor: from now on the editor registers nothing of its own.
    func adopt(_ editor: NSText?) {
        (editor as? NSTextView)?.allowsUndo = false
    }

    /// The user changed the text from `before` to `after` (typing, deleting, pasting).
    func typed(from before: String, to after: String) {
        current = after
        guard let undoManager, !undoManager.isUndoing, !undoManager.isRedoing else { return }
        guard steps.startsStep(from: before, to: after) else { return }
        register(before, on: undoManager)
    }

    /// Something other than typing changed the text (a row arrowed to, a completion accepted): the next letters start a
    /// new step.
    func interrupted() { steps.close() }

    /// The field starts over with `text` (the bar opened, or put text in itself): nothing before it can be undone.
    func reset(text: String) {
        current = text
        steps.close()
        undoManager?.removeAllActions(withTarget: self)
    }

    private func register(_ text: String, on undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { me in me.back(to: text) }
        undoManager.setActionName("Typing")
    }

    /// An undo or a redo: the text that was there goes on the other stack, and `text` comes back.
    private func back(to text: String) {
        guard let undoManager else { return }
        register(current, on: undoManager)
        current = text
        steps.close()
        restore(text)
    }
}
