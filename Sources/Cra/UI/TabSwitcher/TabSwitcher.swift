import AppKit
import Observation
import SwiftUI

/// Arc's tab switcher (ModalItemSwitcher): ⌃Tab shows the space's five most recent tabs
/// the way ⌘Tab shows apps. While ⌃ is held, Tab / ⇧Tab, ` (back) and ← / → move the selection
/// (wrapping) and the pointer picks the card it moves over; releasing ⌃, Return or a click
/// switches, Esc cancels. A quick tap switches to the previous tab without showing the
/// panel. Arc 1.170 measured 27 Oct 2026: no animation on open, move or close.
@MainActor
@Observable
final class TabSwitcher {
    struct Item: Identifiable {
        /// The tab picking the card goes to (a split's pane on screen or used last).
        let id: UUID
        var title: String
        var iconKey: String?
        var snapshot: NSImage?
        /// The tab's space, shown on its card when the switcher spans every space (⌃⌥Tab, #467).
        var space: SpaceLabel? = nil
        /// A split's panes, in pane order (#554); empty for a tab.
        var panes: [Pane] = []
    }

    /// One pane of a split's card: its page and its share of the split's width.
    struct Pane: Identifiable {
        let id: UUID
        var title: String
        var iconKey: String?
        var snapshot: NSImage?
        var width: CGFloat
    }

    struct SpaceLabel {
        var title: String
        var icon: NSImage?
    }

    private(set) var items: [Item] = []
    var selectedIndex = 0
    private(set) var isOpen = false
    /// The space's selection colour and appearance, set before opening.
    var highlight: Color = .clear
    var isDark = true
    var palette: SpacePalette?

    @ObservationIgnored var onShow: () -> Void = {}
    @ObservationIgnored var onHide: () -> Void = {}
    @ObservationIgnored var onCommit: (UUID) -> Void = { _ in }
    /// The direction a key press cycles in when it is one of the switcher's own shortcuts.
    @ObservationIgnored var direction: (NSEvent) -> Int? = { _ in nil }

    @ObservationIgnored private var hold: NSEvent.ModifierFlags = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var showWork: DispatchWorkItem?
    @ObservationIgnored private var pointerAtShow: NSPoint?

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    /// The switcher's shortcut (⌃Tab forward, ⌃⇧Tab back). The first press opens it on the
    /// next (or last) card; the shortcut's modifiers are what holds it open.
    func cycle(_ delta: Int, event: NSEvent?, items make: () -> [Item]) {
        if isOpen { move(delta); return }
        let list = make()
        // Arc 1.171 shows the switcher with one open tab too (its only card); with none, nothing.
        guard !list.isEmpty else { return }
        items = list
        selectedIndex = list.count == 1 ? 0 : delta > 0 ? 1 : list.count - 1
        isOpen = true
        // From a menu or the command bar nothing is held: switch straight away.
        let pressed = event.flatMap { $0.type == .keyDown ? $0.modifierFlags : nil } ?? []
        hold = pressed.intersection([.control, .option, .command])
        guard !hold.isEmpty, NSEvent.modifierFlags.isSuperset(of: hold) else { commit(); return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // Arc waits a moment, so a quick tap never flashes the panel.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isOpen else { return }
            self.pointerAtShow = NSEvent.mouseLocation
            self.onShow()
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TabSwitcherMetrics.showDelay, execute: work)
    }

    /// Testing: open on the second card without a held key. `held`: as if those keys were held, so
    /// the keys go to the switcher as they do from ⌃Tab and letting go of them switches (#696).
    func debugOpen(_ list: [Item], held: NSEvent.ModifierFlags = []) {
        guard !list.isEmpty else { return }
        items = list
        selectedIndex = min(1, list.count - 1)
        isOpen = true
        if !held.isEmpty, monitor == nil {
            hold = held
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        onShow()
    }

    /// Scenarios (#696): "open=1 card=2/5 Title" or "open=0".
    var debugState: String {
        guard isOpen, items.indices.contains(selectedIndex) else { return "open=0" }
        return "open=1 card=\(selectedIndex)/\(items.count) \(items[selectedIndex].title)"
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let n = items.count
        selectedIndex = ((selectedIndex + delta) % n + n) % n
    }

    /// The pointer moved over a card. A panel that opens under a resting pointer keeps its
    /// keyboard selection until the pointer moves.
    func hover(_ index: Int) {
        guard isOpen, NSEvent.mouseLocation != pointerAtShow else { return }
        pointerAtShow = nil
        selectedIndex = index
    }

    func click(_ index: Int) {
        selectedIndex = index
        commit()
    }

    func updateSnapshot(_ id: UUID, _ image: NSImage?) {
        guard let image else { return }
        for i in items.indices {
            if items[i].id == id { items[i].snapshot = image }
            for p in items[i].panes.indices where items[i].panes[p].id == id { items[i].panes[p].snapshot = image }
        }
    }

    func commit() {
        guard isOpen else { return }
        let id = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        close()
        if let id { onCommit(id) }
    }

    func cancel() {
        guard isOpen else { return }
        close()
    }

    private func close() {
        isOpen = false
        showWork?.cancel()
        showWork = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pointerAtShow = nil
        onHide()
    }

    /// Every key goes to the switcher while it is open; releasing the held modifier switches.
    /// A click anywhere else closes it and goes through.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !(event.window is TabSwitcherPanel) { cancel() }
            return event
        }
        if event.type == .flagsChanged {
            if !event.modifierFlags.isSuperset(of: hold) { commit() }
            return event
        }
        if let d = direction(event) { move(d); return nil }
        // Tab, ` (back, #696), the arrows, Return and Esc: TabSwitcherKeys.
        switch TabSwitcherKeys.action(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift)) {
        case .move(let d): move(d)
        case .cancel: cancel()
        case .commit: commit()
        case nil: break
        }
        return nil
    }
}

/// The switcher's floating window: above the page windows, never key (keys come in
/// through the switcher's event monitor), clicks and hover still reach the cards.
final class TabSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }
}
