import AppKit

/// Cra's keyboard while a closing Little Window hands the front back to the app it was opened over (#659): a panel
/// that shows nothing is Cra's key and main window then, so AppKit doesn't make the browser window either, which
/// brought it forward over the app in use on its display (activation raises the key and the main window). It goes
/// once Cra has let go of the front, or after `KeyboardHold.limit` (CraCore decides). A panel, so it isn't Cra in use
/// for other Little Windows' way back (AppDelegate.noteKeyWindow).
@MainActor
final class KeyboardHoldPanel: NSPanel {
    private static var current: KeyboardHoldPanel?

    private var hold: KeyboardHold
    private var resigned: NSObjectProtocol?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Takes the keyboard on `frame`'s display (the closing Little Window's) before it closes.
    static func take(at frame: NSRect) {
        current?.release()
        let panel = KeyboardHoldPanel(at: frame)
        current = panel
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        CraLog.note("Little Window closed: a hold keeps the keyboard until Cra lets go of the front (#659)")
    }

    private init(at frame: NSRect) {
        hold = KeyboardHold(at: Date())
        let spot = NSRect(x: frame.midX, y: frame.midY, width: 1, height: 1)
        super.init(contentRect: spot, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        alphaValue = 0
        hasShadow = false
        ignoresMouseEvents = true
        // hidesOnDeactivate off: it goes in release(), with Cra no longer active, so it hands nothing on.
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        resigned = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(craResigned: true) }
        }
        Timer.scheduledTimer(withTimeInterval: KeyboardHold.limit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(craResigned: false) }
        }
    }

    private func check(craResigned: Bool) {
        guard hold.releases(craResigned: craResigned, at: Date()) else { return }
        release()
    }

    private func release() {
        if let resigned { NotificationCenter.default.removeObserver(resigned) }
        resigned = nil
        orderOut(nil)
        close()
        if Self.current === self { Self.current = nil }
    }
}
