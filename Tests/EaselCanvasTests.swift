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
            makeMouse(type, point, clicks: clicks)
        }
        func makeMouse(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
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
        precondition(sheet.control(field, textView: secondEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is the text box's")
        precondition(window.firstResponder === secondEditor && secondEditor.string.hasSuffix("\n"), "Return starts a new line and typing goes on (#580)")
        precondition(sheet.control(field, textView: secondEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Escape finishes editing")
        precondition(window.firstResponder === sheet, "Escape returns focus to the canvas")
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
        sheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 400, y: 400)))
        sheet.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 450, y: 430)))
        sheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 450, y: 430)))
        precondition(sheet.document.items.count == 1 && sheet.document.items[0].kind == .rectangle, "other canvas tools still draw normally")
        sheet.tool = .pointer
        objectsAndHistory(sheet, window) { makeMouse($0, $1, clicks: $2) }
        drawingAndMenus(window)
        longText()
        severalItems()
        resizeLikeArc()
        endlessCanvas()
        window.close()
        print("Easel canvas: selection, movement, editing and deletion passed")
    }

    // promise: #580
    /// "It should be an endless canvas to put ideas on board, but it isn't" (#580). The canvas was the
    /// window's width and 2436 pt tall: an item further down or to the left was off it. Now the canvas
    /// holds every item with a view's room past it, grows as you scroll toward any edge without moving
    /// what is in view, keeps the title over the home sheet, and zooms (View ▸ Zoom, a pinch).
    @MainActor
    static func endlessCanvas() {
        let low = Easel.Item(kind: .rectangle, frame: .init(x: 200, y: 3000, width: 100, height: 100))
        let left = Easel.Item(kind: .ellipse, frame: .init(x: -400, y: 100, width: 100, height: 100))
        let canvas = EaselCanvasView(document: Easel(items: [low, left]))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
        defer { window.close() }
        let sheet = canvas.sheetView
        guard let scroll = sheet.enclosingScrollView else { fatalError("the canvas scrolls") }
        let clip = scroll.contentView
        func contains(_ outer: NSRect, _ f: Easel.Rect) -> Bool { outer.contains(NSRect(x: f.x, y: f.y, width: f.width, height: f.height)) }
        precondition(contains(sheet.bounds, low.frame), "an item below Arc's 2436 pt is on the canvas: \(sheet.bounds)")
        precondition(contains(sheet.bounds, left.frame), "an item left of the home sheet is on the canvas: \(sheet.bounds)")
        precondition(sheet.bounds.maxY >= 3100 + 700 && sheet.bounds.minX <= -400 - 900, "a view's room past the furthest items: \(sheet.bounds)")
        precondition(sheet.visibleRect.minX == 0 && sheet.visibleRect.minY == 0, "it opens on the home sheet's top left: \(sheet.visibleRect)")
        let title = sheet.subviews.compactMap { $0 as? NSTextField }.first!
        precondition(abs(title.frame.midX - 450) < 1, "the title stays centred over the home sheet: \(title.frame)")

        // Scrolled to the bottom right end of the canvas, there is more past it, and the view stays put.
        clip.scroll(to: NSPoint(x: sheet.frame.width - clip.bounds.width, y: sheet.frame.height - clip.bounds.height))
        scroll.reflectScrolledClipView(clip)
        let atEnd = sheet.visibleRect
        precondition(sheet.bounds.maxX >= atEnd.maxX + 900 && sheet.bounds.maxY >= atEnd.maxY + 700, "scrolling to the end grows the canvas: \(sheet.bounds) \(atEnd)")
        // Up and to the left the same, without the canvas jumping under the view.
        clip.scroll(to: .zero)
        scroll.reflectScrolledClipView(clip)
        let atStart = sheet.visibleRect
        precondition(sheet.bounds.minX <= atStart.minX - 900 && sheet.bounds.minY <= atStart.minY - 700, "scrolling to the start grows it back there: \(sheet.bounds) \(atStart)")
        let anchor = sheet.convert(NSPoint(x: atStart.midX, y: atStart.midY), to: nil)
        canvas.settle()
        let after = sheet.convert(anchor, from: nil)
        precondition(abs(after.x - atStart.midX) < 1 && abs(after.y - atStart.midY) < 1, "the canvas under the view doesn't move when it grows or shrinks")
        precondition(contains(sheet.bounds, low.frame) && contains(sheet.bounds, left.frame), "settling keeps every item on the canvas")

        // An item dragged far up and left stays where it was put.
        func event(_ type: NSEvent.EventType, _ q: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: sheet.convert(q, to: nil), modifierFlags: [], timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let from = NSPoint(x: left.frame.x + 50, y: left.frame.y + 50), to = NSPoint(x: left.frame.x - 950, y: left.frame.y - 750)
        let viewBefore = sheet.visibleRect
        sheet.mouseDown(with: event(.leftMouseDown, from))
        let up = event(.leftMouseDragged, to)
        sheet.mouseDragged(with: up)
        sheet.mouseUp(with: event(.leftMouseUp, to))
        // The drag ended past the view's edge, so the canvas scrolled on under the pointer: the item is
        // where the pointer is on the canvas now, far up and left of the home sheet.
        let under = sheet.convert(up.locationInWindow, from: nil)
        let moved = sheet.document.items.first { $0.id == left.id }!.frame
        precondition(moved.x == under.x - 50 && moved.y == under.y - 50 && moved.x <= -1400 && moved.y <= -700,
                     "an item goes to negative places on the canvas, under the pointer: \(moved) \(under)")
        precondition(to.x - viewBefore.minX < 0 && sheet.visibleRect.minX < viewBefore.minX,
                     "a drag past the edge scrolls the view on: \(viewBefore) → \(sheet.visibleRect)")
        precondition(contains(sheet.bounds, moved), "the canvas takes in the moved item: \(sheet.bounds)")

        // View ▸ Zoom In and Out (and a pinch) magnify the canvas, within Easel.zoomRange.
        precondition(scroll.allowsMagnification && scroll.minMagnification == 0.1 && scroll.maxMagnification == 4, "the canvas zooms with a pinch")
        let middle = NSPoint(x: sheet.visibleRect.midX, y: sheet.visibleRect.midY)
        canvas.zoomLevel = -6
        precondition(abs(scroll.magnification - Easel.magnification(zoomLevel: -6)) < 0.001, "Zoom Out shrinks the canvas: \(scroll.magnification)")
        precondition(abs(sheet.visibleRect.midX - middle.x) < 2 && abs(sheet.visibleRect.midY - middle.y) < 2,
                     "zooming keeps the middle of the view where it was: \(middle) → \(sheet.visibleRect)")
        precondition(abs(canvas.zoomLevel + 6) < 0.001, "the zoom level reads back for View ▸ Zoom")
        precondition(sheet.bounds.width >= sheet.visibleRect.width * 3 - 1, "zoomed out, the room past the view grows with it")
        canvas.zoomLevel = 0
        precondition(scroll.magnification == 1, "Actual Size goes back to 1×")
        print("Easel canvas: endless in every direction, zooms (#580)")
    }

    // promise: #580
    /// A long text widens its box up to 560 pt, then wraps and grows down; Return adds a line; a box saved
    /// by older Cra as one 240 pt line is fitted to its text when the easel opens (#580: "…hover over" lost "over").
    @MainActor
    static func longText() {
        let long = String(repeating: "Lorem ipsum dolor sit amet, hover over ", count: 4)
        let saved = Easel.Item(kind: .text(long, size: 18), frame: .init(x: 40, y: 60, width: 240, height: 26))
        let sheet = EaselSheetView(document: Easel(items: [saved]))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sheet
        sheet.layoutSubtreeIfNeeded()
        defer { window.close() }
        let field = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == saved.id.uuidString }!
        var frame = sheet.document.items[0].frame
        precondition(frame.width == 560 && frame.height > 2 * 27, "an older box is fitted to its whole text when the easel opens: \(frame)")
        precondition(field.frame == NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), "the text field shows the fitted box")
        precondition(field.cell?.wraps == true && field.cell?.isScrollable == false, "the text wraps in its box instead of scrolling out of it")

        precondition(window.makeFirstResponder(field), "the text box takes the keyboard")
        guard let editor = field.currentEditor() as? NSTextView else { fatalError("the text box edits") }
        editor.string = "Short"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        frame = sheet.document.items[0].frame
        precondition(frame.width == 240 && frame.height == 27, "a short text keeps one 240 pt line: \(frame)")
        editor.string = "Lorem ipsum dolor sit amet, consectetur"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        frame = sheet.document.items[0].frame
        precondition(frame.width > 240 && frame.width < 560 && frame.height == 27, "a longer line widens the box on one line: \(frame)")
        let oneLine = frame.height
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        precondition(sheet.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is the text box's")
        frame = sheet.document.items[0].frame
        precondition(sheet.document.items[0].kind == .text("Lorem ipsum dolor sit amet, consectetur\n", size: 18), "Return adds a line to the text")
        precondition(frame.height > oneLine + 15, "the box grows down by the new line: \(frame)")
        precondition(field.frame.height == frame.height, "the text field grows with it")
        editor.string = long
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        frame = sheet.document.items[0].frame
        precondition(frame.width == 560 && frame.height > 2 * 27, "past 560 pt the text wraps and the box grows down: \(frame)")
        print("Easel canvas: long text widens, wraps and takes Return (#580)")
    }

    // promise: #680
    /// Arc 1.174.1's handles (22 Nov 2026): a shape resizes from anywhere along an edge, that side only; a text box takes
    /// its width from its left or right edge and wraps at it, stays as tall as its text (its bottom edge moves nothing),
    /// and keeps that width as it's typed in. Before, text didn't resize and shapes only from their corners.
    @MainActor
    static func resizeLikeArc() {
        let shape = Easel.Item(kind: .rectangle, frame: .init(x: 100, y: 150, width: 200, height: 100))
        let note = Easel.Item(kind: .text("Hello there, a note on the easel", size: 18), frame: .init(x: 100, y: 450, width: 240, height: 27))
        let sheet = EaselSheetView(document: Easel(items: [shape, note]))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sheet
        sheet.layoutSubtreeIfNeeded()
        defer { window.close() }
        let field = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == note.id.uuidString }!
        func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: sheet.convert(p, to: nil), modifierFlags: [], timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        func click(_ p: NSPoint) { sheet.mouseDown(with: event(.leftMouseDown, p)); sheet.mouseUp(with: event(.leftMouseUp, p)) }
        func drag(_ from: NSPoint, _ to: NSPoint) {
            sheet.mouseDown(with: event(.leftMouseDown, from))
            sheet.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)))
            sheet.mouseDragged(with: event(.leftMouseDragged, to))
            sheet.mouseUp(with: event(.leftMouseUp, to))
        }
        func item(_ id: UUID) -> Easel.Item { sheet.document.items.first { $0.id == id }! }

        // The shape: its right edge near the top (not its middle) widens it; its top edge raises it.
        click(NSPoint(x: 200, y: 200))
        drag(NSPoint(x: 300, y: 165), NSPoint(x: 400, y: 165))
        precondition(item(shape.id).frame == .init(x: 100, y: 150, width: 300, height: 100), "a shape's edge resizes that side: \(item(shape.id).frame)")
        drag(NSPoint(x: 330, y: 150), NSPoint(x: 330, y: 120))
        precondition(item(shape.id).frame == .init(x: 100, y: 120, width: 300, height: 130), "its top edge too: \(item(shape.id).frame)")

        // The text box: wider from its right edge, on one line, as tall as before.
        click(NSPoint(x: 150, y: 460))
        let fitted = item(note.id).frame
        drag(NSPoint(x: fitted.x + fitted.width, y: fitted.y + 4), NSPoint(x: fitted.x + fitted.width + 200, y: fitted.y + 4))
        let wide = item(note.id)
        precondition(wide.fixedWidth == true && wide.frame.x == fitted.x && wide.frame.width == fitted.width + 200 && wide.frame.height == fitted.height,
                     "a text box's right edge sets its width: \(fitted) → \(wide.frame)")
        // Narrower than its line: it wraps and grows down, its height still its text's.
        drag(NSPoint(x: wide.frame.x + wide.frame.width, y: wide.frame.y + 4), NSPoint(x: wide.frame.x + 120, y: wide.frame.y + 4))
        let narrow = item(note.id)
        precondition(narrow.frame.width == 120 && narrow.frame.height > fitted.height * 1.5, "narrowed, the text wraps: \(narrow.frame)")
        // Its bottom edge moves nothing.
        drag(NSPoint(x: narrow.frame.x + 60, y: narrow.frame.y + narrow.frame.height), NSPoint(x: narrow.frame.x + 60, y: narrow.frame.y + narrow.frame.height + 80))
        precondition(item(note.id).frame == narrow.frame, "a text box's bottom edge leaves it as tall as its text: \(item(note.id).frame)")
        // Typing keeps the width the drag set (Easel.textBoxWidth): the box grows down, not across.
        field.stringValue = "Hello there, a note on the easel, now a good deal longer than before"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        precondition(item(note.id).frame.width == 120 && item(note.id).frame.height > narrow.frame.height, "typing keeps the width: \(item(note.id).frame)")
        // Undo goes back through the drags; the first one takes the box back to fitting its text.
        sheet.undo(nil); sheet.undo(nil); sheet.undo(nil)
        precondition(item(note.id).fixedWidth == nil && item(note.id).frame.width == fitted.width, "Undo takes the width back: \(item(note.id))")
        print("Easel canvas: shapes resize from their edges, text boxes take a dragged width and keep it (#680)")
    }

    // promise: #580
    /// Picking several items as on the rest of the Mac (#580): ⌘- and ⇧-click add and remove, a drag from
    /// empty canvas draws a box that picks what it touches, and the picked items move, snap, colour,
    /// layer, duplicate, copy, paste, delete and undo together. ⌘A picks them all.
    @MainActor
    static func severalItems() {
        let saved = NSPasteboard.general.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved) }
        let a = Easel.Item(kind: .rectangle, frame: .init(x: 100, y: 150, width: 100, height: 100))
        let b = Easel.Item(kind: .ellipse, frame: .init(x: 300, y: 150, width: 100, height: 100))
        let t = Easel.Item(kind: .text("Note", size: 18), frame: .init(x: 100, y: 450, width: 240, height: 27))
        let sheet = EaselSheetView(document: Easel(items: [a, b, t]))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sheet
        sheet.layoutSubtreeIfNeeded()
        defer { window.close() }
        let field = sheet.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == t.id.uuidString }!
        func event(_ type: NSEvent.EventType, _ p: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: sheet.convert(p, to: nil), modifierFlags: flags, timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        func click(_ p: NSPoint, _ flags: NSEvent.ModifierFlags = []) {
            sheet.mouseDown(with: event(.leftMouseDown, p, flags))
            sheet.mouseUp(with: event(.leftMouseUp, p, flags))
        }
        func drag(_ from: NSPoint, _ to: NSPoint, _ flags: NSEvent.ModifierFlags = [], check: () -> Void = {}) {
            sheet.mouseDown(with: event(.leftMouseDown, from, flags))
            sheet.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), flags))
            sheet.mouseDragged(with: event(.leftMouseDragged, to, flags))
            check()
            sheet.mouseUp(with: event(.leftMouseUp, to, flags))
        }
        func frame(_ id: UUID) -> Easel.Rect { sheet.document.items.first { $0.id == id }!.frame }

        click(NSPoint(x: 150, y: 200))
        precondition(sheet.picked == [a.id], "a click picks one item")
        click(NSPoint(x: 350, y: 200), .command)
        precondition(sheet.picked == [a.id, b.id], "⌘-click adds an item to the picks")
        click(NSPoint(x: 150, y: 200), .shift)
        precondition(sheet.picked == [b.id], "⇧-click takes a picked item out")
        click(NSPoint(x: 150, y: 200), .shift)
        precondition(sheet.picked == [b.id, a.id], "⇧-click adds it back")
        precondition(!sheet.colorPicker.isHidden, "two shapes show the colour picker")
        sheet.setShade(.purple)
        precondition(sheet.document.items[0].shade == .purple && sheet.document.items[1].shade == .purple, "a colour goes to every picked shape")

        // Dragging one of them moves both by the same amount; the text box stays.
        drag(NSPoint(x: 150, y: 200), NSPoint(x: 170, y: 230))
        precondition(frame(a.id) == .init(x: 120, y: 180, width: 100, height: 100) && frame(b.id) == .init(x: 320, y: 180, width: 100, height: 100),
                     "the picked items move together: \(frame(a.id)) \(frame(b.id))")
        precondition(frame(t.id) == t.frame && sheet.picked == [b.id, a.id], "the others stay, and the group stays picked")
        sheet.undo(nil)
        precondition(frame(a.id) == a.frame && frame(b.id) == b.frame, "one Undo puts the whole group back")
        // The group snaps as one box: its left edge 4 pt off the text box's lands on it.
        drag(NSPoint(x: 150, y: 200), NSPoint(x: 154, y: 200))
        precondition(frame(a.id).x == 100 && frame(b.id).x == 300, "the group snaps onto the text box's left edge")

        // A plain click on one of the group, without dragging, picks it alone.
        click(NSPoint(x: 350, y: 200))
        precondition(sheet.picked == [b.id], "a click on one picked item, let go, picks it alone")

        // A drag from empty canvas draws a box; the items it touches are picked as it grows.
        drag(NSPoint(x: 60, y: 120), NSPoint(x: 320, y: 300)) {
            precondition(sheet.band == Easel.Rect(x: 60, y: 120, width: 260, height: 180), "the drag draws the box it spans")
            precondition(sheet.picked == [a.id, b.id], "the box picks every item it touches: \(sheet.picked)")
        }
        precondition(sheet.band == nil && sheet.picked == [a.id, b.id], "letting go keeps the picks and drops the box")
        precondition(frame(a.id) == a.frame, "drawing the box moves nothing")
        // ⌘ held: the box's items flip in the picks from before.
        drag(NSPoint(x: 60, y: 420), NSPoint(x: 160, y: 500), .command)
        precondition(sheet.picked == [a.id, b.id, t.id], "a ⌘-drag box adds what it touches")
        precondition(sheet.colorPicker.isHidden, "a text box among the picks hides the colour picker")
        click(NSPoint(x: 700, y: 600))
        precondition(sheet.picked.isEmpty, "a click on empty canvas picks nothing")
        precondition(window.makeFirstResponder(sheet) && NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: sheet, from: nil),
                     "Select All reaches the canvas")
        precondition(sheet.picked == [a.id, b.id, t.id], "⌘A picks every item")

        // The object menu acts on the whole group.
        click(NSPoint(x: 700, y: 600))
        click(NSPoint(x: 150, y: 200)); click(NSPoint(x: 350, y: 200), .command)
        let menu = sheet.menu(for: event(.rightMouseDown, NSPoint(x: 150, y: 200)))!
        precondition(sheet.picked == [a.id, b.id], "a right click on a picked item keeps the group")
        precondition(menu.items.map(\.title) == ["Bring to Front", "Send to Back", "Delete", "", "Cut", "Copy", "Paste", "", "Duplicate"],
                     "the group's menu: \(menu.items.map(\.title))")
        let front = menu.items.first { $0.title == "Bring to Front" }!
        _ = front.target?.perform(front.action, with: front)
        precondition(sheet.document.items.map(\.id) == [t.id, a.id, b.id], "Bring to Front lifts the group, in its order")

        // Duplicate, copy and paste, and Delete work on every picked item.
        sheet.duplicateSelected()
        precondition(sheet.document.items.count == 5 && sheet.picked.count == 2 && !sheet.picked.contains(a.id), "Duplicate copies each picked item and picks the copies")
        precondition(frame(sheet.picked[0]) == a.frame.offset(by: .init(20, 20)), "each copy sits 20 pt down and right of its original")
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber,
                                      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        sheet.keyDown(with: delete)
        precondition(sheet.document.items.map(\.id) == [t.id, a.id, b.id] && sheet.picked.isEmpty, "Delete removes every picked item")
        click(NSPoint(x: 150, y: 200)); click(NSPoint(x: 150, y: 460), .command)
        precondition(sheet.picked == [a.id, t.id], "a text box can join the picks")
        sheet.copy(nil)
        sheet.paste(nil)
        let pasted = sheet.picked
        precondition(sheet.document.items.count == 5 && pasted.count == 2 && !pasted.contains(a.id), "paste adds every copied item and picks them")
        let pastedText = sheet.document.items.first { pasted.contains($0.id) && $0.kind == t.kind }!
        precondition(sheet.subviews.contains { ($0 as? NSTextField)?.identifier?.rawValue == pastedText.id.uuidString && $0 !== field },
                     "the pasted text box gets its own field")
        sheet.cut(nil)
        precondition(sheet.document.items.count == 3 && sheet.picked.isEmpty, "Cut removes every picked item")
        print("Easel canvas: several items picked, moved, layered, copied and deleted together (#580)")
    }

    /// Every kind of item drawn as Arc draws it (pixels checked), the picker's colours, the canvas menu,
    /// the rows a capture and a picture add, and Cut on a link card.
    @MainActor
    static func drawingAndMenus(_ window: NSWindow) {
        let saved = NSPasteboard.general.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved) }
        // Pictures next to the easel: a red one for links and captures, a blue icon.
        func png(_ color: NSColor, _ name: String) -> String {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            color.setFill(); NSRect(x: 0, y: 0, width: 40, height: 20).fill()
            NSGraphicsContext.restoreGraphicsState()
            let file = UUID().uuidString + "-" + name
            try! rep.representation(using: .png, properties: [:])!.write(to: EaselFiles.pictures(UUID()).appendingPathComponent(file))
            return file
        }
        let red = png(.red, "red.png"), blue = png(.blue, "blue.png")
        let rect = Easel.Item(kind: .rectangle, frame: .init(x: 40, y: 120, width: 100, height: 80))
        let shapes = [rect,
                      Easel.Item(kind: .ellipse, frame: .init(x: 160, y: 120, width: 100, height: 80)),
                      Easel.Item(kind: .arrow(from: .init(280, 200), to: .init(380, 120)), frame: .init(x: 280, y: 120, width: 100, height: 80)),
                      Easel.freehand([.init(400, 150), .init(420, 180), .init(450, 130)])!,
                      Easel.Item(kind: .image(file: red), frame: .init(x: 500, y: 120, width: 80, height: 40))]
        let link = Easel.Item(kind: .link(.init(url: "https://example.com/a", title: "A page", image: red, icon: blue)),
                              frame: .init(x: 40, y: 260, width: 459, height: 324))
        let video = Easel.Item(kind: .link(.init(url: "https://www.youtube.com/watch?v=x", title: "A video", image: red)),
                               frame: .init(x: 520, y: 260, width: 459, height: 324))
        let capture = Easel.Item(kind: .capture(.init(url: "https://example.com/c", title: "Captured", image: red, viewport: .init(800, 600),
                                                      scroll: .init(0, 0), area: .init(x: 0, y: 0, width: 400, height: 200))),
                                 frame: .init(x: 40, y: 620, width: 400, height: 200))
        let sheet = EaselSheetView(document: Easel(items: shapes + [link, video, capture]))
        window.setContentSize(NSSize(width: 1000, height: 900))
        window.contentView = sheet
        sheet.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
        sheet.layoutSubtreeIfNeeded()
        func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: sheet.convert(p, to: nil), modifierFlags: [], timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        // The pointer over the capture shows its bar; over the link, a tooltip with its title and address.
        sheet.mouseMoved(with: event(.mouseMoved, NSPoint(x: 200, y: 700)))
        sheet.mouseMoved(with: event(.mouseMoved, NSPoint(x: 200, y: 400)))
        precondition(sheet.toolTip == "A page\nhttps://example.com/a", "a link card's tooltip is its title and address")
        sheet.mouseMoved(with: event(.mouseMoved, NSPoint(x: 200, y: 700)))
        precondition(sheet.toolTip == nil, "only links have it")
        _ = sheet.pick(index: 0)
        precondition(!sheet.colorPicker.isHidden, "the picked rectangle shows the picker")

        // Drawn into an sRGB bitmap, so the pixels compare with Arc's sRGB colours (a display's
        // own space would shift them).
        let k: CGFloat = 2
        window.colorSpace = .sRGB
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sheet.bounds.width * k), pixelsHigh: Int(sheet.bounds.height * k),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        rep.size = sheet.bounds.size
        sheet.cacheDisplay(in: sheet.bounds, to: rep)
        func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor { rep.colorAt(x: Int(x * k), y: Int(y * k))!.usingColorSpace(.sRGB)! }
        // The expected colour drawn and read back the same way, so colour management cancels out.
        final class Swatch: NSView {
            var color = NSColor.clear
            override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
        }
        func expected(_ color: NSColor) -> NSColor {
            let v = Swatch(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
            v.color = color
            sheet.addSubview(v)
            defer { v.removeFromSuperview() }
            let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
            r.size = v.bounds.size
            v.cacheDisplay(in: v.bounds, to: r)
            return r.colorAt(x: 4, y: 4)!.usingColorSpace(.sRGB)!
        }
        func near(_ c: NSColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1, p3: Bool = false, tolerance: CGFloat = 0.02) -> Bool {
            let e = expected(p3 ? NSColor(displayP3Red: r, green: g, blue: b, alpha: alpha) : NSColor(srgbRed: r, green: g, blue: b, alpha: alpha))
            return abs(c.redComponent - e.redComponent) < tolerance && abs(c.greenComponent - e.greenComponent) < tolerance
                && abs(c.blueComponent - e.blueComponent) < tolerance && abs(c.alphaComponent - e.alphaComponent) < tolerance
        }
        let fill = pixel(90, 160)
        precondition(near(fill, 0x34 / 255, 0xE8 / 255, 0x95 / 255, alpha: 0.75, p3: true), "a rectangle is Vibrant light green (Display P3) at 75 %: \(fill)")
        precondition(near(pixel(40, 160), 0x34 / 255, 0xE8 / 255, 0x95 / 255, p3: true), "with a solid edge")
        precondition(near(pixel(210, 160), 0xF5 / 255, 0x37 / 255, 0x14 / 255, alpha: 0.75), "an ellipse is red")
        precondition(near(pixel(540, 140), 1, 0, 0), "a picture is drawn")
        precondition(near(pixel(260, 400), 1, 0, 0), "a link card's picture fills its top")
        precondition(near(pixel(260, 560), 0, 0, 0), "under it, the black bar")
        precondition(near(pixel(40 + 17 + 13, 260 + 324 - 29.5), 0, 0, 1), "with the site's icon")
        let chip = EaselCards.linkChipRect(in: NSRect(x: 40, y: 260, width: 459, height: 324))
        precondition(near(pixel(chip.minX + 3, chip.minY + 3), 0x1B / 255, 0x1B / 255, 0x1B / 255), "and the ↗ chip")
        precondition(near(pixel(750, 393), 1, 1, 1), "a video has a ▶ over its picture")
        precondition(near(pixel(240, 720), 1, 0, 0), "a capture shows its picture")
        let bar = EaselCards.barRect(in: NSRect(x: 40, y: 620, width: 400, height: 200))
        precondition(near(pixel(bar.midX, bar.minY + 3), 0x25 / 255, 0x28 / 255, 0x32 / 255), "and under the pointer its bar")
        let picker = sheet.colorPicker.frame
        let dot = sheet.colorPicker.dotRect(row: 0, column: 1)
        precondition(near(pixel(picker.minX + dot.midX, picker.minY + dot.midY), 0xFF / 255, 0xD3 / 255, 0x35 / 255), "the picker's yellow is Vibrant's")

        // The canvas menu: Paste, Color Palette ▸ Vibrant / Chill, Use Alignment Guides.
        func run(_ m: NSMenu, _ title: String) {
            let row = m.items.first { $0.title == title }!
            _ = row.target!.perform(row.action!, with: row)
        }
        let canvas = sheet.canvasMenu(at: NSPoint(x: 900, y: 50))
        precondition(canvas.items.map(\.title) == ["Paste", "", "Color Palette", "", "Use Alignment Guides"], "Arc's canvas menu")
        let palette = canvas.items[2].submenu!
        precondition(palette.items.map(\.title) == ["Vibrant", "Chill"] && palette.items[0].state == .on, "Vibrant first, and picked")
        run(palette, "Chill")
        precondition(sheet.document.palette == .chill, "Chill switches the palette")
        let guides = EaselSheetView.usesGuides
        run(canvas, "Use Alignment Guides")
        precondition(EaselSheetView.usesGuides == !guides, "the guides switch")
        EaselSheetView.usesGuides = guides

        // A capture's and a picture's own rows.
        let capRows = sheet.objectMenu(for: capture).items.map(\.title)
        precondition(capRows.suffix(3) == ["Show Live Website", "Copy Capture URL", "Set as Easel Thumbnail"], "a capture's rows: \(capRows)")
        run(sheet.objectMenu(for: capture), "Copy Capture URL")
        precondition(NSPasteboard.general.string(forType: .string) == "https://example.com/c", "Copy Capture URL copies its page's address")
        run(sheet.objectMenu(for: capture), "Set as Easel Thumbnail")
        precondition(sheet.document.thumbnail == capture.id && sheet.objectMenu(for: capture).items.last?.title == "Reset to Default Thumbnail",
                     "the capture stands for the easel, and can stop")
        let picture = shapes[4]
        precondition(sheet.objectMenu(for: picture).items.contains { $0.title == "Add Alt Text…" }, "a picture can be described")

        // Cut on a link card: its address for other apps, and it's gone.
        _ = sheet.pick(index: 5)
        sheet.cut(nil)
        precondition(NSPasteboard.general.string(forType: .string) == "https://example.com/a" && !sheet.document.items.contains { $0.id == link.id },
                     "Cut takes a link card, its address on the pasteboard")
        sheet.paste(nil)
        guard case .link(let back)? = sheet.document.items.last?.kind else { fatalError("Paste puts the card back") }
        precondition(back.icon != nil && back.title == "A page", "with its picture and icon")
        // Another app's crafted items naming a file outside the easel's folder paste nothing.
        let crafted = EaselClip(easel: UUID(), items: [Easel.Item(kind: .image(file: "../../../../etc/hosts"), frame: .init(x: 0, y: 0, width: 10, height: 10))])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(try! JSONEncoder().encode(crafted), forType: .craEaselItems)
        let count = sheet.document.items.count
        sheet.paste(nil)
        precondition(sheet.document.items.count == count, "a pasted item may only name plain picture files")
        print("Easel canvas: Arc's drawing, picker, menus and link cards passed")
    }

    final class FakeLive: EaselLive {
        var onFrame: (NSImage) -> Void = { _ in }
        var onFail: () -> Void = {}
        var closed = false
        var clicks: [Easel.Point] = []
        func click(at p: Easel.Point, open: @escaping (String) -> Void) { clicks.append(p) }
        func close() { closed = true }
    }

    /// Arc 1.172's object menu, undo, copy and paste, links, alignment guides and live captures.
    @MainActor
    static func objectsAndHistory(_ sheet: EaselSheetView, _ window: NSWindow, _ mouse: (NSEvent.EventType, NSPoint, Int) -> NSEvent) {
        let rect = sheet.document.items[0]
        func drag(_ a: NSPoint, _ b: NSPoint) {
            sheet.mouseDown(with: mouse(.leftMouseDown, a, 1))
            sheet.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), 1))
            sheet.mouseDragged(with: mouse(.leftMouseDragged, b, 1))
            sheet.mouseUp(with: mouse(.leftMouseUp, b, 1))
        }
        // Undo and Redo: a move is one step, back and forth.
        drag(NSPoint(x: 420, y: 410), NSPoint(x: 520, y: 510))
        precondition(sheet.document.items[0].frame.x == 500, "the rectangle moved")
        sheet.undo(nil)
        precondition(sheet.document.items[0].frame == rect.frame, "Undo puts a moved item back")
        sheet.redo(nil)
        precondition(sheet.document.items[0].frame.x == 500, "Redo moves it again")
        sheet.undo(nil)
        sheet.undo(nil)
        precondition(sheet.document.items.isEmpty, "Undo takes back the drawing too")
        sheet.redo(nil)
        precondition(sheet.document.items.count == 1, "and Redo brings it back")

        // Copy and Paste: a new item beside the first; Cut takes the original away.
        sheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 420, y: 410), 1))
        sheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 420, y: 410), 1))
        let saved = NSPasteboard.general.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved) }
        sheet.copy(nil)
        sheet.paste(nil)
        precondition(sheet.document.items.count == 2, "Paste adds a copy")
        let pasted = sheet.document.items[1]
        precondition(pasted.id != rect.id && pasted.kind == .rectangle && pasted.frame.x == rect.frame.x + 20, "the copy is new, 20 pt across")

        // Layering from the object menu (Arc's Bring to Front / Send to Back).
        let menu = sheet.objectMenu(for: pasted)
        func run(_ m: NSMenu, _ title: String) {
            let row = m.items.first { $0.title == title }!
            precondition(row.isEnabled, "\(title) is enabled")
            _ = row.target!.perform(row.action!, with: row)
        }
        precondition(menu.items.first { $0.title == "Bring to Front" }?.isEnabled == false, "the top item can't come further forward")
        run(menu, "Send to Back")
        precondition(sheet.document.items.first?.id == pasted.id, "Send to Back puts it under the rest")
        precondition(sheet.document.item(at: .init(Double(rect.frame.x) + 25, Double(rect.frame.y) + 10))?.id == rect.id, "the other one is now on top where they overlap")
        run(sheet.objectMenu(for: sheet.document.items[0]), "Bring to Front")
        precondition(sheet.document.items.last?.id == pasted.id, "Bring to Front puts it on top again")

        // A shape's colour, from Arc's picker over the picked shape.
        let picker = sheet.colorPicker
        precondition(!picker.isHidden && picker.current == .lightGreen, "a picked rectangle shows the picker, light green ticked")
        precondition(picker.frame.maxY <= CGFloat(sheet.document.items.last!.frame.y), "the picker sits above the shape")
        let purple = picker.dotRect(row: 1, column: 2)
        picker.mouseDown(with: mouse(.leftMouseDown, picker.convert(NSPoint(x: purple.midX, y: purple.midY), to: sheet), 1))
        precondition(sheet.document.items.last?.shade == .purple && picker.current == .purple, "a click on purple colours it")
        sheet.undo(nil)
        precondition(sheet.document.items.last?.shade == nil, "and Undo takes the colour back")
        precondition(menu.items.map(\.title) == ["Bring to Front", "Send to Back", "Delete", "", "Cut", "Copy", "Paste", "", "Duplicate"],
                     "Arc's object menu, in its order")

        // A pasted web address is a link card.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://example.com/post", forType: .string)
        var fetched: String?
        EaselHooks.fetchLink = { url, done in fetched = url; done(EaselLinkMetadata(title: "Example post", summary: "Text"), nil, nil) }
        sheet.paste(nil)
        guard case .link(let link) = sheet.document.items.last?.kind else { fatalError("a pasted address becomes a link card") }
        precondition(fetched == "https://example.com/post" && link.title == "Example post" && link.summary == "Text", "the card reads the page")
        NSPasteboard.general.setString("just words", forType: .string)
        let before = sheet.document.items.count
        sheet.paste(nil)
        precondition(sheet.document.items.count == before, "plain text is not a link")
        sheet.deleteSelected()
        precondition(!sheet.document.items.contains { if case .link = $0.kind { return true }; return false }, "the link card deletes")

        // Alignment guides: a move that ends 4 pt off another item's left edge lines up with it.
        let other = sheet.document.items.first { $0.id == rect.id }!
        let movedFrom = sheet.document.items.first { $0.id == pasted.id }!
        let grab = NSPoint(x: movedFrom.frame.x + 25, y: movedFrom.frame.y + 15)  // its middle, clear of the resize corners
        drag(grab, NSPoint(x: other.frame.x + 29, y: grab.y + 200))
        precondition(sheet.document.items.first { $0.id == pasted.id }!.frame.x == other.frame.x, "the moved item snaps to the other's edge")

        // Arc 1.172.2: a click with the rectangle tool places a 200 pt one, centred on the click.
        sheet.tool = .rectangle
        sheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 1000, y: 900), 1))
        sheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 1000, y: 900), 1))
        precondition(sheet.document.items.last?.frame == .init(x: 900, y: 800, width: 200, height: 200), "a click places Arc's 200 pt shape")
        sheet.tool = .pointer

        // A live capture: its page while the easel is on screen, its pictures on the card, gone when it's a screenshot again.
        var made: [FakeLive] = []
        EaselHooks.live = { _, _ in let l = FakeLive(); made.append(l); return l }
        let capture = Easel.Item(kind: .capture(.init(url: "https://example.com", image: "none.png", viewport: .init(1000, 800), scroll: .init(0, 0),
                                                       area: .init(x: 100, y: 100, width: 200, height: 100))),
                                 frame: .init(x: 100, y: 1200, width: 400, height: 200))
        let liveSheet = EaselSheetView(document: Easel(items: [capture]))
        window.contentView = liveSheet
        liveSheet.setLive(true, for: capture.id)
        precondition(made.count == 1, "showing the live website starts its page")
        made[0].onFrame(NSImage(size: NSSize(width: 200, height: 100)))
        precondition(liveSheet.liveImages[capture.id] != nil, "the page's pictures reach the card")
        liveSheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 300, y: 1300), 1))
        liveSheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 300, y: 1300), 1))
        liveSheet.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 300, y: 1300), 1))
        liveSheet.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 300, y: 1300), 1))
        precondition(made[0].clicks == [Easel.Point(100, 50)], "a click on the picked live card reaches the page at the same spot")
        liveSheet.setLive(false, for: capture.id)
        precondition(made[0].closed && liveSheet.liveImages.isEmpty, "back to the screenshot closes the page")
        liveSheet.undo(nil)
        precondition(made.count == 2, "Undo shows the live website again")
        liveSheet.closeLives()
        precondition(made[1].closed, "closing the easel closes its pages")
        EaselHooks.live = nil
        EaselHooks.fetchLink = nil
        print("Easel canvas: undo, copy and paste, layering, colours, links, guides and live captures passed")
    }
}
