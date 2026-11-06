import AppKit
import ObjectiveC

/// AppKit's own answer to "does this window draw its active look", read from a zero-size material that
/// follows its window, the way Arc's sidebar does (SidebarBackdrop.windowActive, GitHub #156).
///
/// It differs from app-active-and-key in one place that shows: a full screen window keeps its active
/// appearance while its Space slides away and the app resigns active, so Arc's sidebar keeps the desktop
/// tint through a ⌃← / ⌃→ round trip. A probe logged that on 5 Nov 2026: `_shouldUseActiveAppearance`
/// stayed on with the app inactive and the window holding neither key nor main, windowed it went off as
/// the window resigned main.
final class ActiveAppearanceProbe: NSVisualEffectView {
    /// AppKit told the view the window's key state changed (`_windowChangedKeyState`, the hook
    /// NSVisualEffectView itself redraws from).
    var onChange: (() -> Void)?

    private static let changedSel = NSSelectorFromString("_windowChangedKeyState")
    private static let answerSel = NSSelectorFromString("_shouldUseActiveAppearance")
    /// Both private hooks exist on this macOS; without them Cra keeps its own rule alone.
    static let available = class_getInstanceMethod(NSVisualEffectView.self, changedSel) != nil
        && class_getInstanceMethod(NSVisualEffectView.self, answerSel) != nil

    init() {
        super.init(frame: .zero)
        state = .followsWindowActiveState
        blendingMode = .withinWindow
    }

    required init?(coder: NSCoder) { fatalError() }

    /// nil when AppKit doesn't have the hook or the view isn't in a window.
    var isActive: Bool? {
        guard Self.available, window != nil, let imp = class_getMethodImplementation(NSVisualEffectView.self, Self.answerSel) else { return nil }
        typealias Answer = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: Answer.self)(self, Self.answerSel)
    }

    @objc func _windowChangedKeyState() {
        if Self.available, let imp = class_getMethodImplementation(NSVisualEffectView.self, Self.changedSel) {
            typealias Changed = @convention(c) (AnyObject, Selector) -> Void
            unsafeBitCast(imp, to: Changed.self)(self, Self.changedSel)
        }
        onChange?()
    }
}
