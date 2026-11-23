import AppKit

/// The command bar selects the address it opens with (`CommandTextField`). A long one must show
/// its start, as in Arc, not the end the field was scrolled to before (X report, 23 Nov 2026).
/// A real NSTextField and field editor in a window that is never shown.
@main
enum FieldEditorSelectionTests {
    private static var checks = 0
    private static let sheet = "https://docs.google.com/spreadsheets/d/1AbCdEfGhIjKlMnOpQrStUvWxYzhGOKyPN-tQ5yZ_09zEaPjy5HVRZsh_vKc/edit?gid=0#gid=0"

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        longAddressShowsItsStart()
        startShownWhenFieldWasScrolledToTheEnd()
        shortAddressUnchanged()
        print("Field editor selection: \(checks) checks passed")
    }

    /// The bar opening on a long address: all of it selected, its first character in view.
    @MainActor
    private static func longAddressShowsItsStart() {
        let (window, field) = make()
        field.stringValue = sheet
        window.makeFirstResponder(field)
        let editor = editor(of: field)
        editor.selectAllShowingStart()
        check(editor.selectedRange == NSRange(location: 0, length: (sheet as NSString).length), "whole address selected")
        check(firstCharacterVisible(editor), "first character in view")
    }

    /// The field still has focus and sits at the end of the last address (End, typing, or the
    /// caret the bar puts after a previewed row). The next address comes up selected and showed
    /// only its tail.
    @MainActor
    private static func startShownWhenFieldWasScrolledToTheEnd() {
        let (window, field) = make()
        window.makeFirstResponder(field)
        field.stringValue = sheet
        editor(of: field).moveToEndOfLine(nil)
        check(!firstCharacterVisible(editor(of: field)), "setup: field scrolled to the end")
        let next = sheet.replacingOccurrences(of: "gid=0#gid=0", with: "gid=1#gid=1")
        field.stringValue = next
        let editor = editor(of: field)
        editor.selectAllShowingStart()
        check(editor.selectedRange == NSRange(location: 0, length: (next as NSString).length), "whole address selected")
        check(firstCharacterVisible(editor), "first character in view after the field was at the end")
        check(clipX(editor) <= 2, "scrolled back to the start (x \(clipX(editor)))")
    }

    /// An address that fits is selected and stays put.
    @MainActor
    private static func shortAddressUnchanged() {
        let (window, field) = make()
        field.stringValue = "https://arc.net"
        window.makeFirstResponder(field)
        let editor = editor(of: field)
        let before = clipX(editor)
        editor.selectAllShowingStart()
        check(editor.selectedRange == NSRange(location: 0, length: 15), "short address selected")
        check(clipX(editor) == before, "short address not moved")
        check(firstCharacterVisible(editor), "short address in view")
    }

    // MARK: - Helpers

    /// The command bar's field as `CommandTextField.makeField` sets it up, 400 pt wide.
    @MainActor
    private static func make() -> (NSWindow, NSTextField) {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 500, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.frame = NSRect(x: 10, y: 5, width: 400, height: 30)
        window.contentView?.addSubview(field)
        return (window, field)
    }

    @MainActor
    private static func editor(of field: NSTextField) -> NSTextView {
        guard let editor = field.currentEditor() as? NSTextView else { fatalError("no field editor") }
        return editor
    }

    @MainActor
    private static func clipX(_ editor: NSTextView) -> CGFloat { editor.visibleRect.minX }

    @MainActor
    private static func firstCharacterVisible(_ editor: NSTextView) -> Bool {
        guard let layout = editor.layoutManager, let container = editor.textContainer else { return false }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += editor.textContainerOrigin.x
        return editor.visibleRect.contains(NSPoint(x: rect.midX, y: editor.visibleRect.midY))
    }

    private static func check(_ condition: Bool, _ what: String) {
        checks += 1
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
            exit(1)
        }
    }
}
