import AppKit

@main
enum FloatingSidebarTests {
    private static var checks = 0

    @MainActor
    static func main() {
        geometry()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1400, height: 880),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let shell = ShellView(frame: NSRect(origin: .zero, size: window.frame.size))
        window.contentView = shell
        let sidebar = FloatingSidebarController(shell: shell, window: window, palette: { SpacePalette() })
        sidebar.sidebarHidden = { true }
        // Do not install the pointer timer or post input events. The real controller
        // and AppKit animation completions run with an offscreen disposable panel.
        sidebar.show()
        expect(sidebar.isShown && shell.sidebarDetached, "show attaches the sidebar to its panel")
        let panel = window.childWindows!.first!

        sidebar.hide(animated: true)
        expect(!sidebar.isShown && shell.sidebarDetached, "animated hide remains in flight before completion")
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "an old hide completion must not remove a newly revealed panel")
        expect(shell.sidebarHost.window === panel, "the revealed sidebar retains its native panel owner")

        // Multiple animation completions can be queued; only the latest show owns it.
        sidebar.hide(animated: true)
        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "rapid edge re-entry leaves the latest reveal visible")

        sidebar.hide(animated: true)
        sidebar.prepareForAnchoring()
        expect(!sidebar.isShown && !shell.sidebarDetached && shell.sidebarHost.superview === shell,
               "anchoring during hide immediately brings the sidebar home")
        expect(shell.floatingSidebar && panel.parent == nil && !panel.isVisible,
               "anchoring preserves the floating start frame while removing its panel")
        drainAnimations()
        expect(shell.floatingSidebar && shell.sidebarHost.superview === shell,
               "a stale hide completion must not overwrite the anchoring start state")

        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.hide(animated: false)
        expect(!shell.sidebarDetached && panel.parent == nil && !panel.isVisible,
               "a synchronous hide finishes an in-flight animated hide immediately")
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !panel.hasShadow,
               "late show and hide completions cannot revive a hidden panel or shadow")

        sidebar.show()
        sidebar.hide(animated: true)
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !shell.floatingSidebar,
               "an uninterrupted hide still reattaches the sidebar normally")
        window.close()
        print("Floating sidebar: \(checks) checks passed")
    }

    private static func geometry() {
        // Nonzero bounds also check that both paths use shell-local geometry.
        let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 20, y: 100), in: bounds), "left edge reveals")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25, y: 100), in: bounds), "5 pt in reveals, as in Arc")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 26, y: 100), in: bounds), "6 pt in does not reveal, as in Arc")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 16, y: 100), in: bounds), "just outside the window reveals, as in Arc")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 15.9, y: 100), in: bounds), "further outside does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 9.9), in: bounds), "above the window does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 890.1), in: bounds), "below the window does not reveal")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 17, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "the outside reveal strip does not hide what it revealed")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 380, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "panel margin and leave slack are included in the retention boundary")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 380.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the shared retention boundary hides after release")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the window hides after release")
        for button in [1, 2, 4] {
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 380.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar beyond the leave slack during a gesture")
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar outside the moving window during a gesture")
        }
    }

    private static func drainAnimations() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}

// Lightweight dependencies for compiling the production controller without CEF.
// They provide layout/theme data only; lifecycle and animation code is not copied.
struct SpacePalette {
    var vibrant = false
    var isDark = false
}

final class PaletteBackgroundView: NSView {
    var palette: SpacePalette
    init(palette: SpacePalette) { self.palette = palette; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

enum CraMetrics {
    static let contentInset: CGFloat = 10
    static let titleRowCenter: CGFloat = 24
}

final class CraTuning {
    static let shared = CraTuning()
    let material: NSVisualEffectView.Material = .sidebar
    let darkBlur = false
    let liftActive: CGFloat = 0.1
}

final class ShellView: NSView {
    let sidebarHost = NSView()
    let resizeHandle = NSView()
    var sidebarWidth: CGFloat = 328
    var contentFullscreen = false
    var sidebarDetached = false
    var floatingSidebar = false
    struct Frames { let sidebar: NSRect }

    override init(frame: NSRect) {
        super.init(frame: frame)
        sidebarHost.wantsLayer = true
        addSubview(sidebarHost)
        addSubview(resizeHandle)
    }
    required init?(coder: NSCoder) { fatalError() }

    func frames(sidebarVisible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat) -> Frames {
        let margin = FloatingSidebarGeometry.margin
        return Frames(sidebar: NSRect(x: margin, y: margin, width: width, height: bounds.height - 2 * margin))
    }
}
