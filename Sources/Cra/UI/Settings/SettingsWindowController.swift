import AppKit
import SwiftUI

/// Callbacks the panes hand back to the app.
struct SettingsActions {
    var importData: () -> Void = {}
    var rebuildArcProfiles: () -> Void = {}
    var openURL: (String) -> Void = { _ in }
    /// A page in a space on that profile (nil is Default), e.g. its chrome://settings/languages.
    var openProfilePage: (String, UUID?) -> Void = { _, _ in }
    var exportDiagnostics: () -> Void = {}
    var newProfile: () -> Void = {}
}

/// The panes in Dia's Settings sidebar (Dia 1.54.2: Account, Tabs, Privacy, Profiles, Skills,
/// Apps, Shortcuts, Advanced). Cra has no account or AI skills/apps; General
/// (system integration) and Extensions take rows instead. Max is Arc's Max pane, for the
/// features Cra runs on the Mac's own Apple Intelligence model.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, tabs, max, privacy, profiles, extensions, shortcuts, performance, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .tabs: return "Tabs"
        case .max: return "Max"
        case .privacy: return "Privacy"
        case .profiles: return "Profiles"
        case .extensions: return "Extensions"
        case .shortcuts: return "Shortcuts"
        case .performance: return "Performance"
        case .advanced: return "Advanced"
        }
    }

    /// Dia's sidebar glyphs are SF Symbols (compared against the running Dia's icons).
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .tabs: return "square.on.square"
        // macOS 15.1 added Apple's mark; before it, sparkles.
        case .max: return NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil ? "apple.intelligence" : "sparkles"
        case .privacy: return "hand.raised"
        case .profiles: return "person"
        case .extensions: return "puzzlepiece.extension"
        case .shortcuts: return "keyboard"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .advanced: return "gearshape.2"
        }
    }
}

/// Selected pane plus the back/forward history behind the toolbar pill.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var pane: SettingsPane = .general
    private(set) var back: [SettingsPane] = []
    private(set) var forward: [SettingsPane] = []
    /// The window is on screen: panes that refresh (Performance) stop while it is closed or covered.
    var isOpen = false
    /// Counts each time Settings is brought up: panes showing what changed elsewhere (a profile's
    /// languages, set on Chromium's page) read it again.
    private(set) var shown = 0
    func didShow() { shown += 1 }

    func show(_ p: SettingsPane) {
        guard p != pane else { return }
        back.append(pane)
        forward = []
        pane = p
    }
    func goBack() {
        guard let p = back.popLast() else { return }
        forward.append(pane)
        pane = p
    }
    func goForward() {
        guard let p = forward.popLast() else { return }
        back.append(pane)
        pane = p
    }
}

/// Dia's Settings window: 778×509, close button only, a 204 pt full-height source-list
/// sidebar in an NSSplitViewController and a unified 52 pt toolbar with the back/forward
/// pill and the pane title after the sidebar (measured on Dia 1.54.2, see
/// docs/arc-reverse-engineering.md "Dia Settings window"). The pill and title are drawn by
/// the content view under the (empty) toolbar: macOS 26 would wrap toolbar items in a
/// shared glass capsule that Dia does not have.
@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let nav = SettingsNavigation()

    func show(_ pane: SettingsPane) { nav.show(pane) }
    func didShow() { nav.didShow() }

    init(store: SidebarStore, bindings: KeyBindingRegistry, sync: SettingsSyncService, actions: SettingsActions) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsMetrics.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // The content view draws the pill and title under the toolbar; the titlebar must not
        // blur them, and Dia has no separator line under its toolbar.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false

        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SettingsSidebar(nav: nav)))
        // macOS 26 insets the sidebar panel 8 pt; Dia's split sits at 204 with its list 8 in.
        sidebar.minimumThickness = SettingsMetrics.sidebarWidth - 8
        sidebar.maximumThickness = SettingsMetrics.sidebarWidth - 8
        sidebar.canCollapse = false
        let content = NSHostingController(rootView: SettingsContent(nav: nav, actions: actions)
            .environment(store).environment(bindings).environment(sync))
        let contentItem = NSSplitViewItem(viewController: content)
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(contentItem)
        split.splitView.dividerStyle = .thin
        window.contentViewController = split

        let toolbar = NSToolbar(identifier: "cra.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        // Size last: the toolbar and full-size content change how the frame is derived.
        window.setFrame(NSRect(origin: .zero, size: SettingsMetrics.windowSize), display: false)
        window.centerOnTestScreen()
        // On screen: shown and not entirely covered (the window needn't be key).
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [nav] note in
                MainActor.assumeIsolated {
                    guard let w = note.object as? NSWindow else { return }
                    let open = note.name != NSWindow.willCloseNotification && w.occlusionState.contains(.visible)
                    if nav.isOpen != open { nav.isOpen = open }
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        nil
    }
}

/// Dia's back/forward pill: 69×38 capsule, black 25% in dark mode, two chevrons.
struct SettingsNavPill: View {
    let nav: SettingsNavigation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", enabled: !nav.back.isEmpty) { nav.goBack() }
            arrow("chevron.right", enabled: !nav.forward.isEmpty) { nav.goForward() }
        }
        .frame(width: SettingsMetrics.navPillSize.width, height: SettingsMetrics.navPillSize.height)
        .background(Capsule().fill(Color.black.opacity(scheme == .dark ? 0.25 : 0.06)))
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(enabled ? 0.75 : 0.3))
                .frame(width: SettingsMetrics.navPillSize.width / 2, height: SettingsMetrics.navPillSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The toolbar row over the content: pill 10 in from the split, title text 10 after it.
struct SettingsToolbarRow: View {
    let nav: SettingsNavigation
    var body: some View {
        HStack(spacing: 10) {
            SettingsNavPill(nav: nav)
            Text(nav.pane.title).font(.system(size: 15, weight: .bold))
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .frame(height: SettingsMetrics.toolbarHeight)
    }
}

/// Dia's source list: 28 pt rows inset 8, 20 pt glyph 20 in, label 49 in. The selected row
/// is accent-filled with white text while the window is key, otherwise a grey fill with
/// accent-coloured text.
struct SettingsSidebar: View {
    let nav: SettingsNavigation
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsPane.allCases) { row($0) }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ p: SettingsPane) -> some View {
        let selected = nav.pane == p
        let key = activeState == .key
        return Button { nav.show(p) } label: {
            HStack(spacing: 9) {
                Image(systemName: p.symbol)
                    .font(.system(size: 15))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(selected && key ? Color.white : Color.primary)
                Text(p.title)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? (key ? Color.white : Color.accentColor) : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? (key ? Color.accentColor : Color.primary.opacity(0.1)) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsContent: View {
    let nav: SettingsNavigation
    let actions: SettingsActions

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbarRow(nav: nav)
            Group {
                switch nav.pane {
                case .general: GeneralPane()
                case .tabs: TabsPane()
                case .max: MaxPane()
                case .privacy: PrivacyPane(actions: actions)
                case .profiles: ProfilesPane(nav: nav, actions: actions)
                case .extensions: ExtensionsPane(actions: actions)
                case .shortcuts: ShortcutsPane()
                case .performance: PerformancePane(nav: nav, actions: actions)
                case .advanced: AdvancedPane(actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}
