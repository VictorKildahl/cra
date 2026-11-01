import AppKit
import SwiftUI

/// What Arc's space menu opens (the header's ••• and its right-click menu).
extension MainWindowController {
    /// Change Space Icon…: Arc's picker in a popover pointing up at the header's icon.
    func showSpaceIconPicker(space: Space, anchor: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: space.theme.palette.isDark ? .darkAqua : .aqua)
        let id = space.id, store = self.store
        let set: (String, String?) -> Void = { [weak popover] emoji, symbol in
            guard var s = store.space(id) else { return }
            s.emoji = emoji
            s.symbol = symbol
            store.updateSpace(s)
            popover?.performClose(nil)
        }
        let picker = SpaceIconPicker(current: space.emoji, currentSymbol: space.symbol, onPick: { set($0, nil) },
                                     onPickSymbol: { set("", $0) }, onRemove: { set("", nil) })
        // A fixed size: NSPopover placed itself for the hosting view's first, larger size and then
        // shrank toward its bottom-left corner, which left it 52 pt low with the arrow off-centre.
        let host = NSHostingController(rootView: picker)
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: 272, height: 272)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 272, height: 272)
        guard let content = anchor.window?.contentView else { return }
        var rect = anchor.convert((anchor as? SpaceHeaderView)?.iconRect ?? anchor.bounds, to: content)
        // Arc's arrow tip sits a point higher, at the icon box's last row.
        rect.origin.y += content.isFlipped ? -1 : 1
        popover.show(relativeTo: rect, of: content, preferredEdge: content.isFlipped ? .maxY : .minY)
    }

    /// Edit Theme Color…: Arc's editor in a panel against the sidebar's edge at the window's top,
    /// applying every change at once. Escape or a click outside closes it.
    func showSpaceStyleEditor(space: Space) {
        guard let window else { return }
        if let open = window.childWindows?.first(where: { $0 is StyleEditorPanel }) { open.close() }
        let store = self.store, id = space.id
        let editor = SpaceStyleEditor(theme: space.theme) { theme in
            guard var s = store.space(id) else { return }
            s.theme = theme
            store.updateSpace(s)
        }
        // The card sits 12 pt into its 382 × 534 pt window (19 pt above the bottom), room for the shadow.
        let size = NSSize(width: 382, height: 534)
        let x = (window.frame.minX + (shell.sidebarVisible ? shell.sidebarWidth : 0)).rounded()
        let panel = StyleEditorPanel(contentRect: NSRect(x: x, y: window.frame.maxY - size.height, width: size.width, height: size.height))
        let host = NSHostingView(rootView: editor.shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.top, 12).padding(.horizontal, 13.5).padding(.bottom, 19))
        host.sizingOptions = []
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }
    /// Set Profile ▸ New Profile…: Arc's dialog over the dimmed window; Next makes the profile and
    /// moves the space into it (pages already open reload in it, BrowserManager).
    func showNewProfileDialog(forSpace id: UUID) {
        guard let window else { return }
        let store = self.store
        DialogOverlayWindow.present(over: window) { close in
            NewProfileDialog(onCreate: { name in
                store.setProfile(store.createProfile(name: name).id, forSpace: id)
                close()
            }, onCancel: close)
        }
    }
    /// Manage Spaces…: the Library on its Spaces page, every space side by side.
    func showManageSpaces() { showLibrary(.spaces) }
}

/// The theme editor's window: borderless and see-through around its card; closes on Escape or a
/// click anywhere else in the app.
final class StyleEditorPanel: NSPanel {
    private var monitor: Any?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown {
                // Escape closes it wherever the key goes (SwiftUI keeps it from cancelOperation).
                guard e.keyCode == 53 else { return e }
                self.close()
                return nil
            }
            if e.window !== self { self.close() }
            return e
        }
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        parent?.removeChildWindow(self)
        super.close()
    }
}
