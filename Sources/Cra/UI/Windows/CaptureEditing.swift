import AppKit

/// Capture's image editor as the overlay sees it (#851): CaptureEditorView in the app, a stand-in in the capture
/// harness, which doesn't build the easel canvas.
@MainActor
protocol CaptureEditing: NSView {
    /// The editor closed: the capture with what was drawn on it.
    var onDone: (CGImage) -> Void { get set }
    func focus()
    /// Puts the drawing into the capture and closes, as a click on the dark page around the card does.
    func finish()
}

@MainActor
enum CaptureEditors {
    /// Makes the editor for a capture over a page of that frame; set at launch.
    static var make: (NSRect, CGImage) -> (any CaptureEditing)? = { _, _ in nil }
}
