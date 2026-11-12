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
    /// Advanced ▸ Reset Translated-site Prompts (Arc): the translate choices of every profile are forgotten.
    var resetTranslatedSitePrompts: () -> Void = {}
    /// Shortcuts ▸ Learn the Essential Shortcuts: the floating card of the basics (Help ▸ Essential Keyboard Shortcuts).
    var essentialShortcuts: () -> Void = {}
}

extension SettingsTab {
    /// The glyph over the tab's name. Arc draws its own; these are the SF Symbols closest to them.
    var symbol: String {
        switch self {
        case .sync: return "icloud"
        case .general: return "gearshape"
        case .profiles: return "person"
        // macOS 15.1 added Apple's mark; before it, sparkles.
        case .max: return NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil ? "apple.intelligence" : "sparkles"
        case .links: return "macwindow.on.rectangle"
        case .shortcuts: return "keyboard"
        case .icon: return "app.dashed"
        case .advanced: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .extensions: return "puzzlepiece.extension"
        }
    }
}

/// The tab Settings is on. Arc's window shows its tabs in a toolbar and switches between them at once.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var tab: SettingsTab = .first
    /// The window is on screen: panes that refresh (Performance) stop while it is closed or covered.
    var isOpen = false
    /// Counts each time Settings is brought up: panes showing what changed elsewhere (a profile's
    /// languages, set on Chromium's page) read it again.
    private(set) var shown = 0
    func didShow() { shown += 1 }

    func show(_ t: SettingsTab) { if t != tab { tab = t } }
}

/// Arc's Settings window: 684 × 650, fixed, close button only, the tab's name as its title and a toolbar of tabs
/// 32 pt down (measured on Arc 1.172.2, 11 and 12 Nov 2026, GitHub #372). It opens on the first tab every time, in
/// the same place, and a tab switch is instant. The tabs are drawn by the content view under a transparent title
/// bar: macOS 26 would wrap toolbar items in a glass capsule that Arc's don't have.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let nav = SettingsNavigation()

    func show(_ tab: SettingsTab) { nav.show(tab) }
    var debugPane: String { nav.tab.rawValue }
    func didShow() { nav.didShow() }
    /// Arc opens Settings on its first tab each time it is opened, not on the one used last.
    func showFirstTabIfClosed() { if window?.isVisible != true { nav.show(.first) } }

    init(store: SidebarStore, bindings: KeyBindingRegistry, sync: SettingsSyncService, actions: SettingsActions) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsMetrics.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = SettingsTab.first.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = SettingsPalette.window
        let root = SettingsRoot(nav: nav, actions: actions) { [weak window] tab in window?.title = tab.title }
            .environment(store).environment(bindings).environment(sync)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(SettingsMetrics.windowSize)
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
}

/// The tabs over the pane of the chosen one.
struct SettingsRoot: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    let titleChanged: (SettingsTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(nav: nav)
                .padding(.top, SettingsMetrics.tabBarTop)
                .frame(height: SettingsMetrics.tabBarTop + SettingsMetrics.tabBarHeight, alignment: .top)
            Rectangle().fill(Color(nsColor: SettingsPalette.tabLine)).frame(height: 1)
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Scroll views can draw into the ignored titlebar safe area. Keep every
                // pane inside its viewport below the tabs.
                .clipped()
        }
        .background(Color.settingsWindow)
        // Arc's title, the tab's name, centred and dimmed in the title bar (the system's would sit beside the buttons).
        .overlay(alignment: .top) {
            Text(nav.tab.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                .frame(height: 28)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: nav.tab) { _, tab in titleChanged(tab) }
    }

    @ViewBuilder private var pane: some View {
        switch nav.tab {
        case .sync: SyncPane()
        case .general: GeneralPane(nav: nav)
        case .profiles: ProfilesPane(nav: nav, actions: actions)
        case .max: MaxPane()
        case .links: LinksPane()
        case .shortcuts: ShortcutsPane(actions: actions)
        case .icon: IconPane()
        case .advanced:
            // Performance is Cra's own, in no Arc tab: what the recorder saw, at the foot of Advanced.
            SettingsCardPane {
                AdvancedPane(actions: actions).settingsNested()
                SettingsHeader("Performance").padding(.top, 20)
                PerformancePane(nav: nav, actions: actions).settingsNested()
            }
        case .privacy: PrivacyPane(actions: actions)
        case .extensions: ExtensionsPane(actions: actions)
        }
    }
}

/// Arc's tab buttons: the glyph over the name, 55 pt wide at least, the chosen one on a rounded pill with its
/// glyph and name in blue (dark: a navy pill with a hairline; light: a white one with a soft shadow).
struct SettingsTabBar: View {
    let nav: SettingsNavigation

    var body: some View {
        HStack(spacing: 1) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(tab: tab, selected: nav.tab == tab) { nav.show(tab) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19))
                    .frame(height: 24)
                Text(tab.title).font(.system(size: 12))
            }
            .foregroundStyle(selected ? Color.settingsBlue : Color.secondary)
            .padding(.horizontal, 5.5)
            .frame(minWidth: SettingsMetrics.tabMinWidth, minHeight: SettingsMetrics.tabPillHeight)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: SettingsMetrics.tabCorner, style: .continuous)
                        .fill(Color(nsColor: SettingsPalette.selectedTab))
                        .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.tabCorner, style: .continuous)
                            .strokeBorder(Color(nsColor: SettingsPalette.selectedTabBorder), lineWidth: 1))
                        .shadow(color: .black.opacity(scheme == .light ? 0.12 : 0), radius: 6, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
