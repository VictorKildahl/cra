import AppKit

/// ⌘Z in the command bar undoes what was typed (#809). The bar's inline completion writes the field's whole text on
/// each keystroke, which emptied the field editor's own undo history, so ⌘Z did nothing. A real NSTextField, its
/// field editor and the window's undo manager, in a window that is never shown; `Bar` writes the field as
/// CommandTextField does (the typed text plus the rest of a completion, selected) and keeps a FieldTypingUndo.
@main
enum FieldTypingUndoTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        undoTakesBackWhatWasTypedPastTheCompletion()
        redoTypesItAgain()
        deletingIsAStepOfItsOwn()
        textTheBarPutInIsNotUndone()
        print("Command bar typing undo: \(checks) checks passed")
    }

    /// "git" typed letter by letter with github.com completing it: ⌘Z empties the field, as in Arc.
    // promise: #809
    @MainActor
    private static func undoTakesBackWhatWasTypedPastTheCompletion() {
        let bar = Bar()
        bar.type("git")
        check(bar.field.stringValue == "github.com", "completed to github.com (\(bar.field.stringValue))")
        bar.undo()
        check(bar.field.stringValue == "", "⌘Z took back the typing (\"\(bar.field.stringValue)\")")
        check(bar.typed == "", "the bar lists for what is typed now")
    }

    // promise: #809
    @MainActor
    private static func redoTypesItAgain() {
        let bar = Bar()
        bar.type("git")
        bar.undo()
        bar.redo()
        check(bar.field.stringValue == "git", "⇧⌘Z brought back the typing, without a completion (\"\(bar.field.stringValue)\")")
    }

    /// Typing, then deleting: two steps.
    // promise: #809
    @MainActor
    private static func deletingIsAStepOfItsOwn() {
        let bar = Bar()
        bar.type("xyzw")
        bar.deleteBackward()
        check(bar.field.stringValue == "xyz", "deleted a letter (\(bar.field.stringValue))")
        bar.undo()
        check(bar.field.stringValue == "xyzw", "first ⌘Z brings the letter back (\(bar.field.stringValue))")
        bar.undo()
        check(bar.field.stringValue == "", "second ⌘Z takes back the typing (\(bar.field.stringValue))")
    }

    /// The bar opening with an address: ⌘Z doesn't take it away, nor bring back what was typed before.
    // promise: #809
    @MainActor
    private static func textTheBarPutInIsNotUndone() {
        let bar = Bar()
        bar.type("old")
        bar.open(with: "https://arc.net/")
        bar.undo()
        check(bar.field.stringValue == "https://arc.net/", "the bar's own text stays (\(bar.field.stringValue))")
        bar.type("z")
        bar.undo()
        check(bar.field.stringValue == "https://arc.net/", "⌘Z after typing over it brings the address back (\(bar.field.stringValue))")
    }

    @MainActor
    private final class Bar: NSObject, NSTextFieldDelegate {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        var undoer: FieldTypingUndo!
        var typed = ""
        private var writing = false
        private let completions = ["github.com", "gitlab.com"]

        override init() {
            super.init()
            window.contentView?.addSubview(field)
            field.delegate = self
            undoer = FieldTypingUndo(field: field) { [weak self] text in self?.restore(text) }
            window.makeFirstResponder(field)
            undoer.adopt(field.currentEditor())
        }

        var editor: NSTextView { field.currentEditor() as! NSTextView }

        func type(_ text: String) {
            for c in text {
                editor.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0))
                endOfEvent()
            }
        }
        func deleteBackward() {
            editor.deleteBackward(nil)
            endOfEvent()
        }
        /// Each key is an event of its own in the app, and the undo manager closes its group as the event ends.
        private func endOfEvent() { RunLoop.current.run(until: Date()) }
        // ⌘Z and ⇧⌘Z as the Edit menu sends them: up the responder chain from the field editor.
        func undo() { _ = editor.tryToPerform(Selector(("undo:")), with: nil) }
        func redo() { _ = editor.tryToPerform(Selector(("redo:")), with: nil) }

        func open(with text: String) {
            undoer.reset(text: text)
            write(text)
            typed = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !writing else { return }
            let text = field.stringValue
            undoer.typed(from: typed, to: text)
            typed = text
            // The completion: the field's whole text written again, the rest selected (CommandTextField.applyCompletion).
            if let c = completions.first(where: { $0.hasPrefix(text) && $0 != text && !text.isEmpty }) {
                write(c)
                editor.selectedRange = NSRange(location: (text as NSString).length, length: (c as NSString).length - (text as NSString).length)
            }
        }

        private func restore(_ text: String) {
            write(text)
            typed = text
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }

        private func write(_ text: String) {
            writing = true
            field.stringValue = text
            writing = false
        }
    }

    private static func check(_ ok: Bool, _ what: String) {
        guard ok else {
            print("FAIL: \(what)")
            exit(1)
        }
        checks += 1
    }
}
