import AppKit
import SwiftUI

/// For scenario hooks: a click on a SwiftUI button in one of Cra's windows, posted the way a person's click arrives
/// (a mouse down and up through the app's event queue to the window), so SwiftUI's own button handling runs. An
/// accessibility press would skip it, and with it bugs that live there (the updater's "Downloads in progress", X 17
/// Nov 2026). SwiftUI shows no accessibility children to its own process, so buttons that hooks click say where they
/// are with `clickTarget(_:)`.
@MainActor
enum DialogClick {
    /// Only a scripted Cra (scenarios, CRA_COMMAND_FILE) keeps the frames.
    static let recording = ProcessInfo.processInfo.environment["CRA_COMMAND_FILE"] != nil
    /// Each target's frame in its window's SwiftUI root, by title.
    static var frames: [String: CGRect] = [:]

    /// Clicks the middle of the target `title` in `window`. False when it has no frame there.
    @discardableResult
    static func post(_ title: String, in window: NSWindow) -> Bool {
        guard let frame = frames[title], let root = window.contentView, root.bounds.contains(NSPoint(x: frame.midX, y: frame.midY)) else { return false }
        let mid = NSPoint(x: frame.midX, y: root.isFlipped ? frame.midY : root.bounds.height - frame.midY)
        let at = root.convert(mid, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                 pressure: type == .leftMouseDown ? 1 : 0) else { return false }
            NSApp.postEvent(event, atStart: false)
        }
        return true
    }
}

extension View {
    /// A button scenario hooks can click by `title` (DialogClick).
    @ViewBuilder func clickTarget(_ title: String) -> some View {
        if DialogClick.recording {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { DialogClick.frames[title] = frame }
            }
        } else {
            self
        }
    }
}
