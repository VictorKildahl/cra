import AppKit

/// A borderless button that runs a closure: SwiftUI's `Button { } label: { Image(…) }` with
/// `.buttonStyle(.plain)`, or a small push button with a title.
final class ClosureButton: NSButton {
    var onPress: () -> Void

    /// A plain glyph: no bezel, no hover, the symbol in `tint`.
    init(symbol: String, size: CGFloat, weight: NSFont.Weight = .regular, tint: NSColor = .labelColor, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        image = SidebarSymbols.image(symbol, size: size, weight: weight)
        contentTintColor = tint
        setButtonType(.momentaryChange)
        target = self
        action = #selector(fire)
        sizeToFit()
    }

    /// A push button with a title.
    init(title: String, controlSize: NSControl.ControlSize = .regular, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .push
        self.controlSize = controlSize
        font = .systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        target = self
        action = #selector(fire)
        sizeToFit()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { onPress() }
}

/// SwiftUI's `.background(.regularMaterial, in: RoundedRectangle(cornerRadius:))` with the
/// hairline `.strokeBorder(Color.primary.opacity(0.1))` most of Cra's floating bits wear.
final class MaterialCardView: NSVisualEffectView {
    init(radius: CGFloat, material: NSVisualEffectView.Material = .popover, border: Bool = true) {
        super.init(frame: .zero)
        self.material = material
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = border ? 1 : 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        }
    }
}

extension NSView {
    /// DevTools (and a page) are Chromium child windows of the main window. After a click in one,
    /// AppKit treated the next click on the main window as the one that activates it, and a toolbar
    /// button needed a second click (GitHub #42), even once AppKit itself already had the main window
    /// key. Chrome draws all of it in one window, so buttons take that click while focus is in this
    /// window or its children; a click into an inactive Cra still only activates it.
    var takesClickFromChildWindow: Bool {
        guard NSApp.isActive, let window, let key = NSApp.keyWindow else { return false }
        return key === window || key.parent === window
    }
}
