import AppKit
import SwiftUI

/// What Arc's space menu opens (the header's ••• and its right-click menu).
extension MainWindowController {
    /// Change Space Icon…: Arc's picker in a popover pointing up at the header's icon.
    func showSpaceIconPicker(space: Space, anchor: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
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

    /// Edit Theme Color…: Arc's editor in a panel against the sidebar's edge at the window's top.
    /// Every change shows in the space at once but is written only when the editor closes, as in
    /// Arc (offline Arc 1.171: StorableSidebar.json changed on Escape, not on the swatch press).
    func showSpaceStyleEditor(space: Space, beside anchor: NSView? = nil) {
        guard let window else { return }
        if let open = window.childWindows?.first(where: { $0 is StyleEditorPanel }) { open.close() }
        let store = self.store, id = space.id
        let editor = SpaceStyleEditor(theme: space.theme) { theme in store.previewTheme(theme, forSpace: id) }
        // The card sits 12 pt into its 382 × 534 pt window (19 pt above the bottom), room for the shadow.
        let size = NSSize(width: 382, height: 534)
        // From a Spaces page card Arc puts it flush with the card's right edge.
        let x = (anchor.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)).maxX } }
            ?? window.frame.minX + (shell.sidebarVisible ? shell.sidebarWidth : 0)).rounded()
        let panel = StyleEditorPanel(contentRect: NSRect(x: x, y: window.frame.maxY - size.height, width: size.width, height: size.height)) {
            store.endThemePreview(forSpace: id, keep: true)
        }
        let host = NSHostingView(rootView: editor.shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.top, 12).padding(.horizontal, 13.5).padding(.bottom, 19))
        host.sizingOptions = []
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Set Profile ▸ New Profile…: Arc's dialog over the dimmed window; Next asks which spaces use
    /// the profile (this one ticked) and Create Profile moves them into it (pages already open
    /// reload in it, BrowserManager).
    func showNewProfileDialog(forSpace id: UUID) {
        guard let window else { return }
        showNewProfileDialog(over: window, ticked: [id])
    }

    /// Settings ▸ Profiles ▸ Create Profile…: the same dialog over Settings, no space ticked.
    func showNewProfileDialog(over window: NSWindow, ticked: Set<UUID> = []) {
        DialogPanel.present(over: window) { close in
            NewProfileDialog(spaces: profileSpaces, ticked: ticked, onCreate: { [weak self] name, ids in
                self?.createProfile(name: name, forSpaces: ids)
                close()
            }, onCancel: close)
        }
    }

    /// Spaces ▸ Change Profile: Arc's "Change <space>’s Profile" dialog for the focused space.
    func showChangeProfileDialog(forSpace id: UUID) {
        guard let window, let space = store.space(id) else { return }
        let store = self.store
        DialogPanel.present(over: window) { close in
            ChangeProfileDialog(space: space, profiles: store.profiles, spaces: profileSpaces, onChange: { p in
                store.setProfile(p, forSpace: id)
                close()
            }, onCreate: { [weak self] name, ids in
                self?.createProfile(name: name, forSpaces: ids)
                close()
            }, onCancel: close)
        }
    }

    /// The spaces a profile can be given to: every space but incognito ones, in sidebar order.
    private var profileSpaces: [Space] { store.orderedSpaces.filter { !store.isIncognito(space: $0.id) } }

    private func createProfile(name: String, forSpaces ids: Set<UUID>) {
        let p = store.createProfile(name: name)
        for s in profileSpaces where ids.contains(s.id) { store.setProfile(p.id, forSpace: s.id) }
    }
    /// Manage Spaces…: the Library on its Spaces page, every space side by side.
    func showManageSpaces() { showLibrary(.spaces) }
}

/// The theme editor's window: borderless and see-through around its card. Escape, a click anywhere
/// else in the app, the app going to the background or the browser window closing closes it and
/// keeps the change, as Arc's editor does.
final class StyleEditorPanel: NSPanel {
    private var monitor: Any?
    private var resignObserver: Any?
    private var parentObserver: Any?
    private var onClose: (() -> Void)?

    init(contentRect: NSRect, onClose: @escaping () -> Void) {
        self.onClose = onClose
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
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // The browser window closing under it commits too.
        parentObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                                                queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let w = note.object as? NSWindow, w === self.parent else { return }
                self.close()
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        let done = onClose
        onClose = nil
        done?()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let parentObserver { NotificationCenter.default.removeObserver(parentObserver) }
        parentObserver = nil
        parent?.removeChildWindow(self)
        super.close()
    }
}
