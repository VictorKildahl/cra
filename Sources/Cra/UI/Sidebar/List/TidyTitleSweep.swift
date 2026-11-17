import AppKit

/// Owns the native pieces of one pinned-title sweep, including its delayed cleanup.
@MainActor
final class TidyTitleSweep {
    private struct Active {
        let token: UUID
        let oldTitle: NSTextField
        let sparkles: CALayer
        let title: CALayer?
        let subtitle: CALayer?
        let row: CALayer?
        let didEnd: () -> Void
    }

    private var active: Active?
    var isActive: Bool { active != nil }

    /// Install ownership before assigning the new masks, so replacing a sweep clears only
    /// the previous one's native state.
    func begin(token: UUID, oldTitle: NSTextField, sparkles: CALayer,
               title: NSTextField, subtitle: NSTextField, row: CALayer?,
               duration: TimeInterval, didEnd: @escaping () -> Void) {
        end()
        active = Active(token: token, oldTitle: oldTitle, sparkles: sparkles,
                        title: title.layer, subtitle: subtitle.layer, row: row, didEnd: didEnd)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.end(token: token) }
    }

    func update(effectToken: UUID?, editing: Bool) {
        guard let active, editing || active.token != effectToken else { return }
        end()
    }

    func end(token: UUID? = nil) {
        guard let active, token == nil || active.token == token else { return }
        self.active = nil
        active.oldTitle.removeFromSuperview()
        active.sparkles.removeFromSuperlayer()
        active.title?.mask = nil
        active.subtitle?.mask = nil
        active.row?.zPosition = 0
        active.didEnd()
    }
}
