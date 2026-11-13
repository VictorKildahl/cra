import AppKit

/// The command bar's NSTextField with Chrome/Arc-style inline completion: the
/// completed suffix is inserted selected, so typing replaces it and
/// Backspace removes it without re-completing. CommandBarView calls `update`
/// whenever the controller changes.
@MainActor
final class CommandTextField {
    let controller: CommandBarController
    let field: NSTextField
    private let coordinator: Coordinator

    init(controller: CommandBarController) {
        self.controller = controller
        coordinator = Coordinator(controller: controller)
        field = Self.makeField(controller: controller, coordinator: coordinator)
    }

    func update() {
        Self.update(field, controller: controller, coordinator: coordinator)
        // A completion needs the field's editor, which exists once the field is first responder
        // (made so on the next turn when the bar opens): apply what is pending again then.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Self.update(self.field, controller: self.controller, coordinator: self.coordinator)
        }
    }

    private static func makeField(controller: CommandBarController, coordinator: Coordinator) -> NSTextField {
        let field = NSTextField(string: controller.fieldText)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18, weight: .medium)
        // Arc's typed text is (230,231,233) on its dark bar.
        field.textColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.9, alpha: 1) : .labelColor }
        field.placeholderAttributedString = placeholder(controller.placeholder)
        field.delegate = coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        coordinator.field = field
        return field
    }

    private static func placeholder(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            // Arc 1.172.1 live: the placeholder's ink peaks at (163,162,162).
            .foregroundColor: NSColor(white: 0.64, alpha: 1),
        ])
    }

    private static func update(_ field: NSTextField, controller: CommandBarController, coordinator coord: Coordinator) {
        // Runs on every keystroke: rebuild the placeholder only when its text changes.
        if field.placeholderAttributedString?.string != controller.placeholder {
            field.placeholderAttributedString = placeholder(controller.placeholder)
        }
        if coord.appliedVersion != controller.fieldTextVersion {
            coord.appliedVersion = controller.fieldTextVersion
            coord.suppressChange = true
            field.stringValue = controller.fieldText
            coord.lastTyped = controller.fieldText
            coord.suppressChange = false
            let selected = controller.fieldTextSelected
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                guard let editor = field.currentEditor() else { return }
                if selected { editor.selectAll(nil) } else { editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0) }
            }
        }
        if coord.appliedPreview != controller.previewVersion {
            coord.appliedPreview = controller.previewVersion
            coord.showPreview(controller.previewText)
        }
        if controller.previewText != nil {
            // Arrowed onto a row; the field shows that row, not a completion.
        } else if let c = controller.result.inlineCompletion, controller.allowCompletion, coord.pendingCompletion != c {
            coord.applyCompletion(c)
        } else if controller.result.inlineCompletion == nil {
            coord.pendingCompletion = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let controller: CommandBarController
        weak var field: NSTextField?
        var appliedVersion = 0
        var appliedPreview = 0
        var lastTyped = ""
        var suppressChange = false
        var pendingCompletion: String?

        init(controller: CommandBarController) { self.controller = controller }

        func applyCompletion(_ completion: String) {
            guard let field, let editor = field.currentEditor() else { return }
            let typed = lastTyped
            guard completion.lowercased().hasPrefix(typed.lowercased()), completion.count > typed.count else { return }
            let remainder = String(completion.dropFirst(typed.count))
            pendingCompletion = completion
            suppressChange = true
            field.stringValue = typed + remainder
            editor.selectedRange = NSRange(location: (typed as NSString).length, length: (remainder as NSString).length)
            suppressChange = false
        }

        /// Show the arrowed-to row's text, or restore what was typed.
        func showPreview(_ text: String?) {
            guard let field else { return }
            let shown = text ?? controller.query
            suppressChange = true
            field.stringValue = shown
            lastTyped = shown
            pendingCompletion = nil
            field.currentEditor()?.selectedRange = NSRange(location: (shown as NSString).length, length: 0)
            suppressChange = false
        }

        /// If a completion suffix is selected, Enter means "go there". A completion an open tab
        /// supplies leads the list as its "Switch to Tab" row, and Enter switches to that tab, as
        /// in Arc 1.171 ("youtube" → youtube.com with a pinned YouTube). Asking again for the
        /// completed address put the typed row first and opened the site in a new tab instead
        /// (reported on X, 1 Nov 2026).
        private func acceptSelectedCompletion(_ textView: NSTextView) {
            guard pendingCompletion != nil, textView.selectedRange.length > 0 else { return }
            if controller.result.inlineCompletion == pendingCompletion, controller.result.items.first?.tabID != nil { return }
            lastTyped = textView.string
            controller.update(query: textView.string, allowCompletion: false)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !suppressChange, let field else { return }
            let text = field.stringValue
            let deleting = text.count < lastTyped.count || (pendingCompletion != nil && text == lastTyped)
            lastTyped = text
            pendingCompletion = nil
            controller.update(query: text, allowCompletion: !deleting)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                controller.moveSelection(by: 1); return true
            case #selector(NSResponder.moveUp(_:)):
                controller.moveSelection(by: -1); return true
            case #selector(NSResponder.insertNewline(_:)):
                acceptSelectedCompletion(textView)
                // Shift-Return: Instant Links on a search row; Return everywhere else.
                if NSApp.currentEvent.map({ $0.type == .keyDown && $0.modifierFlags.intersection([.shift, .control, .option, .command]) == .shift }) == true {
                    controller.commitInstantLinks()
                } else {
                    controller.commit()
                }
                return true
            // The key bindings have nothing for ⌘Return, so the field editor sends noop:, never
            // insertNewline: (GitHub #85).
            case Selector(("noop:")) where NSApp.currentEvent.map { $0.type == .keyDown && Shortcut.isCommandReturn(keyCode: $0.keyCode, modifiers: $0.modifierFlags.rawValue) } == true:
                acceptSelectedCompletion(textView)
                controller.commitInBackground()
                return true
            // ⌥Return, which a field editor reads as a line break.
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                acceptSelectedCompletion(textView)
                controller.commitInSplit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if controller.scope != nil { controller.cancelScope() } else { controller.close() }
                return true
            case #selector(NSResponder.insertTab(_:)) where controller.enterScope():
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
                if pendingCompletion != nil, textView.selectedRange.length > 0 {
                    let text = textView.string
                    textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                    lastTyped = text
                    pendingCompletion = nil
                    controller.update(query: text, allowCompletion: false)
                    return true
                }
                return selector == #selector(NSResponder.insertTab(_:))
            case #selector(NSResponder.deleteBackward(_:)):
                if controller.scope != nil, textView.string.isEmpty {
                    controller.leaveScope()
                    return true
                }
                if pendingCompletion != nil, textView.selectedRange.length > 0 {
                    // Remove the suggestion, keep what was typed.
                    let typed = lastTyped
                    pendingCompletion = nil
                    suppressChange = true
                    textView.string = typed
                    textView.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
                    suppressChange = false
                    controller.update(query: typed, allowCompletion: false)
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}
