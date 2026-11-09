import AppKit

@main
enum EaselCanvasTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let item = Easel.Item(kind: .text("Move this text", size: 18), frame: .init(x: 150, y: 200, width: 240, height: 26))
        let sheet = EaselSheetView(document: Easel(items: [item]))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sheet
        sheet.layoutSubtreeIfNeeded()
        let field = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == item.id.uuidString }!
        let title = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0 !== field }!
        let pill = sheet.subviews.compactMap { $0 as? EaselSizePill }.first!
        var changes: [Easel] = []
        sheet.onChange = { changes.append($0) }

        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: sheet.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0)!
        }
        func click(_ point: NSPoint, clicks: Int = 1) {
            let hit = sheet.hitTest(sheet.convert(point, to: sheet.superview))!
            hit.mouseDown(with: mouse(.leftMouseDown, point, clicks: clicks))
            hit.mouseUp(with: mouse(.leftMouseUp, point, clicks: clicks))
        }
        let point = NSPoint(x: 180, y: 210)
        precondition(sheet.hitTest(sheet.convert(point, to: sheet.superview)) === sheet, "unselected text clicks reach the canvas")
        click(point)
        precondition(window.firstResponder === sheet && field.currentEditor() == nil, "one click selects the block without editing")
        precondition(!pill.isHidden, "selecting text shows its size controls")
        let pillOrigin = pill.frame.origin
        let hit = sheet.hitTest(sheet.convert(point, to: sheet.superview))!
        hit.mouseDown(with: mouse(.leftMouseDown, point))
        hit.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 220, y: 240)))
        hit.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 220, y: 240)))
        precondition(sheet.document.items[0].frame.x == 190 && sheet.document.items[0].frame.y == 230, "dragging text moves the block")
        precondition(field.frame.origin == NSPoint(x: 190, y: 230), "the text view follows the model")
        precondition(pill.frame.origin == NSPoint(x: pillOrigin.x + 40, y: pillOrigin.y + 30), "size controls follow the moved text")
        precondition(changes.last == sheet.document, "the moved document is saved")

        click(NSPoint(x: 220, y: 240), clicks: 2)
        guard let editor = field.currentEditor() as? NSTextView else { fatalError("double click must start editing") }
        precondition(window.firstResponder === editor, "editing keeps normal text input")
        precondition(sheet.hitTest(sheet.convert(NSPoint(x: 220, y: 240), to: sheet.superview)) !== sheet, "editing text keeps its mouse events")
        editor.string = "Edited text"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        precondition(sheet.document.items[0].kind == .text("Edited text", size: 18), "text edits update the document")
        precondition(sheet.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Escape finishes editing")
        precondition(window.firstResponder === sheet && field.currentEditor() == nil, "Escape returns focus to the canvas")
        click(NSPoint(x: 220, y: 240), clicks: 2)
        let secondEditor = field.currentEditor() as! NSTextView
        secondEditor.deleteBackward(nil)
        precondition(sheet.document.items.count == 1 && field.superview === sheet, "deleting characters while editing keeps the block")
        precondition(!sheet.control(field, textView: secondEditor, doCommandBy: #selector(NSResponder.moveLeft(_:))), "ordinary editing commands stay with the text editor")
        precondition(sheet.control(field, textView: secondEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Enter finishes editing")
        precondition(window.firstResponder === sheet, "Enter returns focus to the canvas")
        click(NSPoint(x: 600, y: 400))
        precondition(pill.isHidden, "clicking empty canvas clears the text selection")
        click(NSPoint(x: 220, y: 240))
        precondition(!pill.isHidden && field.currentEditor() == nil, "an edited block can be selected again")
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2,
                                      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: 51)!
        sheet.keyDown(with: delete)
        precondition(sheet.document.items.isEmpty && field.superview == nil, "Delete removes the selected text block")
        precondition(changes.last?.items.isEmpty == true && pill.isHidden, "deleting persists the document and hides size controls")
        precondition(sheet.hitTest(sheet.convert(NSPoint(x: title.frame.midX, y: title.frame.midY), to: sheet.superview)) === title, "the title remains directly editable")
        for code: UInt16 in [51, 117] {
            sheet.tool = .text
            var toolFinished = false
            sheet.onToolDone = { sheet.tool = .pointer; toolFinished = true }
            click(NSPoint(x: 180, y: 300))
            precondition(toolFinished && sheet.document.items.count == 1, "the text tool creates one block and returns to selection")
            let created = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == sheet.document.items[0].id.uuidString }!
            guard let createdEditor = created.currentEditor() as? NSTextView else { fatalError("new text starts editing immediately") }
            precondition(sheet.control(created, textView: createdEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "new text exits editing with Escape")
            sheet.duplicateSelected()
            precondition(sheet.document.items.count == 2, "selected text can be duplicated")
            let forwardDelete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 3,
                                                 windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                 isARepeat: false, keyCode: code)!
            sheet.keyDown(with: forwardDelete)
            precondition(sheet.document.items.count == 1, "either Delete key removes the selected duplicate only")
            click(NSPoint(x: 180, y: 300))
            sheet.keyDown(with: forwardDelete)
            precondition(sheet.document.items.isEmpty, "newly created text can also be selected and deleted")
        }
        sheet.tool = .rectangle
        click(NSPoint(x: 400, y: 400))
        sheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 400, y: 400)))
        sheet.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 450, y: 430)))
        sheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 450, y: 430)))
        precondition(sheet.document.items.count == 1 && sheet.document.items[0].kind == .rectangle, "other canvas tools still draw normally")
        window.close()
        print("Easel canvas: selection, movement, editing and deletion passed")
    }
}
