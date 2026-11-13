import AppKit

/// A button's second action (#416): a press held for `delay` acts while the button is still down,
/// and the release that follows does nothing more. (A right-click is the button's own
/// `rightMouseDown`; a ⌃-click is a plain click, as on Arc's Back and Forward.)
@MainActor
final class ButtonHold {
    /// Arc 1.172 (LongPressButton): its menu showed 0.79–0.85 s after the press, live 13 Nov 2026.
    static let delay: TimeInterval = 0.75
    /// Runs the block after the delay; returns what cancels it. A test passes its own clock.
    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let schedule: Schedule
    private var cancelTimer: (() -> Void)?
    private var fired = false

    static let timer: Schedule = { delay, block in
        let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { block() } }
        return { t.invalidate() }
    }

    init(schedule: Schedule? = nil) { self.schedule = schedule ?? Self.timer }

    /// Starts timing a press; false: the button goes on with its own press as well.
    @discardableResult
    func down(_ event: NSEvent, enabled: Bool, secondary: (() -> Void)?) -> Bool {
        cancel()
        fired = false
        guard enabled, let secondary else { return false }
        cancelTimer = schedule(Self.delay) { [weak self] in
            guard let self else { return }
            self.cancelTimer = nil
            self.fired = true
            secondary()
        }
        return false
    }

    /// true: the second action ran for this press, so the release must not run the first.
    func up() -> Bool {
        cancel()
        defer { fired = false }
        return fired
    }

    func cancel() {
        cancelTimer?()
        cancelTimer = nil
    }
}
