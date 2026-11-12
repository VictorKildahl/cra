import AppKit
import SwiftUI

/// Arc's Shortcuts tab (Arc 1.172.2, GitHub #372): "Start with the basics" and a button for the Essential Shortcuts,
/// a card with a search field (an action's name, or its keys as words: "command e") over one flat list of actions
/// with their keys on white caps, and a column on the right with the chosen action's keys as two big caps, its name
/// and what it does, who gets its keys when a page wants them too (#374), "Reset Shortcut to Default" and a "…" menu.
struct ShortcutsPane: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var query = ""
    @State private var selectedID: String?

    private static let listWidth: CGFloat = 340
    private static let rowHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 30) {
            basics
            HStack(alignment: .top, spacing: 16) {
                list
                detail
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, SettingsMetrics.paneInset)
        .padding(.top, SettingsMetrics.paneTop)
        .padding(.bottom, SettingsMetrics.paneBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: openRequested)
        .onChange(of: nav.shortcut) { _, _ in openRequested() }
    }

    /// Use Both's "Edit the shortcut" opens the pane on its action.
    private func openRequested() {
        guard let id = nav.shortcut else { return }
        nav.shortcut = nil
        query = ""
        selectedID = id
    }

    // MARK: Basics

    private var basics: some View {
        HStack(spacing: 8) {
            Text("Start with the basics").font(.system(size: 13)).foregroundStyle(.secondary)
            Button { actions.essentialShortcuts() } label: {
                Label("Learn the Essential Shortcuts", systemImage: "command.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color.settingsBlue))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.14)))
        .frame(maxWidth: .infinity)
    }

    // MARK: List

    /// Every action but Help's, by name; the ones the user changed first, as Arc's "Customized Shortcuts".
    private var visible: [(title: String, actions: [KeyAction])] {
        let all = bindings.actions.filter { $0.section != .help && ShortcutSearch.matches(query, name: $0.name, shortcuts: $0.shortcuts) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let customized = all.filter { bindings.isOverridden($0.id) }
        let rest = all.filter { !bindings.isOverridden($0.id) }
        return [("Customized Shortcuts", customized), ("Default Shortcuts", rest)].filter { !$0.1.isEmpty }
    }

    private func conflicts(of a: KeyAction) -> [KeyAction] {
        guard let s = a.primary else { return [] }
        return bindings.actions.filter { $0.id != a.id && $0.shortcuts.contains(s) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("Type a feature name or shortcut (like “Command E”)").foregroundStyle(.secondary))
                    .textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Color.primary.opacity(0.08))
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(visible, id: \.title) { group in
                        Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.leading, 16).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        Rectangle().fill(Color.settingsHairline).frame(height: 1)
                        ForEach(Array(group.actions.enumerated()), id: \.element.id) { i, a in
                            row(a)
                            if i < group.actions.count - 1 { SettingsCardDivider().padding(.horizontal, 14) }
                        }
                    }
                }
            }
        }
        .frame(width: Self.listWidth)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous).fill(Color(nsColor: SettingsPalette.card)))
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous).strokeBorder(Color.settingsHairline, lineWidth: 1))
    }

    private func row(_ a: KeyAction) -> some View {
        let selected = a.id == selectedID
        return Button { selectedID = a.id } label: {
            HStack(spacing: 8) {
                Text(a.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 8)
                Text(a.shortcuts.isEmpty ? "---" : a.shortcuts.map(\.display).joined(separator: " "))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 64, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color.white))
            }
            .padding(.horizontal, 24)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color(nsColor: SettingsPalette.selectedRow) : Color.clear)
                .padding(.horizontal, 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var chosen: KeyAction? { selectedID.flatMap { bindings.action($0) } }

    private var detail: some View {
        let a = chosen
        let caps: [String] = a.map { $0.primary?.caps ?? [] } ?? ["⌘", "☺"]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array((caps.isEmpty ? ["", ""] : caps).prefix(4).enumerated()), id: \.offset) { _, cap in
                    BigKeyCap(glyph: cap, dim: a != nil && caps.isEmpty)
                }
            }
            Text(a?.name ?? "Custom Shortcuts").font(.system(size: 14, weight: .semibold))
                .padding(.top, 22)
            Text(a.map { ShortcutDescriptions.text(for: $0) } ?? "Change shortcuts for your favorite actions, and even choose whether Cra or a website takes priority.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let a {
                ShortcutRecorder(action: a).padding(.top, 14)
                let c = conflicts(of: a)
                if !c.isEmpty {
                    Text((c.count == 1 ? "This shortcut conflicts with another shortcut: " : "This shortcut conflicts with other shortcuts: ")
                         + c.map(\.name).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                if !a.shortcuts.isEmpty { priority(a) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let a {
                    Button("Reset Shortcut to Default") { bindings.resetShortcuts(for: a.id) }
                        .disabled(!bindings.isOverridden(a.id))
                } else {
                    Button("Reset All Shortcuts") { bindings.resetOverrides() }
                        .disabled(!bindings.actions.contains { bindings.isOverridden($0.id) })
                }
                Menu {
                    Button("Remove Shortcut") { if let a { bindings.setShortcuts([], for: a.id) } }
                        .disabled(a == nil || a?.shortcuts.isEmpty == true)
                    Divider()
                    Button("Reset All Shortcuts") { bindings.resetOverrides() }
                    Button("Extension Shortcuts…") { actions.openURL("chrome://extensions/shortcuts") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.14)))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Arc 1.172.2: under a rule, a pop-up of who gets the keys when the page wants them too, and a
    /// line saying what that means. Only for an action with a shortcut.
    private func priority(_ a: KeyAction) -> some View {
        let p = bindings.priority(of: a.id)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.settingsHairline).frame(height: 1)
                .padding(.top, 22)
            Picker("Priority", selection: Binding(get: { p }, set: { bindings.setPriority($0, for: a.id) })) {
                ForEach(ShortcutPriority.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            .padding(.top, 16)
            Text(p.subtitle)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }
}

/// One of the big keys over a shortcut's name: a light cap on a darker rim, the glyph in blue.
private struct BigKeyCap: View {
    let glyph: String
    var dim = false
    private static let rim = Color(.sRGB, red: 0.1, green: 0.38, blue: 0.9)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.rim)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(.sRGB, red: 0.86, green: 0.92, blue: 1), Color(.sRGB, red: 0.7, green: 0.8, blue: 0.97)], startPoint: .top, endPoint: .bottom))
                .padding(.init(top: 4, leading: 4, bottom: 8, trailing: 4))
            Group {
                if glyph == "☺" { Image(systemName: "face.smiling").font(.system(size: 26, weight: .semibold)) }
                else { Text(glyph).font(.system(size: glyph.count > 2 ? 20 : 30, weight: .bold)) }
            }
            .foregroundStyle(Self.rim)
            .offset(y: -2)
        }
        .frame(width: 64, height: 64)
        .opacity(dim ? 0.4 : 1)
        .accessibilityHidden(true)
    }
}

/// Records a new shortcut: click it, then press the new keys; Esc cancels, ⌫ removes the shortcut.
struct ShortcutRecorder: View {
    let action: KeyAction
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (action.shortcuts.isEmpty ? "Record Shortcut" : "Change Shortcut"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(recording ? Color.settingsBlue : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: SettingsMetrics.controlHeight)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color.primary.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous).strokeBorder(recording ? Color.settingsBlue : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut. Esc cancels, ⌫ removes it.")
        .onChange(of: action.id) { _, _ in stop() }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ e: NSEvent) {
        if e.keyCode == 53 { stop(); return }                               // esc
        if e.keyCode == 51 || e.keyCode == 117 { bindings.setShortcuts([], for: action.id); stop(); return }  // ⌫ / ⌦
        guard let s = Shortcut.from(event: e) else { return }
        bindings.setShortcuts([s], for: action.id)
        stop()
    }
}

/// One-line descriptions for the detail column (Dia: "Create a new tab.").
@MainActor
enum ShortcutDescriptions {
    static func text(for a: KeyAction) -> String {
        if let description = LiveFolderPluginStore.shared.entry(forCommand: a.id)?.package.manifest.command?.description { return description }
        if let t = table[a.id] { return t }
        if a.id.hasPrefix("item"), let n = a.id.dropFirst(4).first { return "Switch to the \(n). tab in the sidebar." }
        if a.id.hasPrefix("space"), let n = a.id.dropFirst(5).first { return "Switch to the \(n). space." }
        if a.id.hasPrefix("moveTabToSpace"), let n = a.id.dropFirst(14).first { return "Move the current tab, or a Little Window's page, to the \(n). space and switch to it." }
        return a.name + "."
    }

    private static let table: [String: String] = [
        "newTab": "Create a new tab.",
        "newWindow": "Open a new window.",
        "newIncognitoWindow": "Open a window that keeps no history, cookies or tabs once closed.",
        "newLittleWindow": "Open a small, disposable window for a quick look.",
        "reopenClosedTab": "Bring back the tab you closed last.",
        "editURL": "Open the command bar to search or enter a URL.",
        "newFolder": "Create a folder in the sidebar.",
        "newSpace": "Create a new space.",
        "closeWindow": "Close the current window.",
        "closeTab": "Close the current tab.",
        "capturePage": "Take a screenshot of the page.",
        "print": "Print the page.",
        "copyURL": "Copy the page’s URL.",
        "copyURLMarkdown": "Copy the page’s title and URL as a Markdown link.",
        "find": "Search for text on the page.",
        "findNext": "Jump to the next match.",
        "findPrevious": "Jump to the previous match.",
        "toggleSidebar": "Show or hide the sidebar.",
        "toggleToolbar": "Show or hide the toolbar above the page.",
        "stop": "Stop loading the page.",
        "reload": "Reload the page.",
        "hardReload": "Reload the page, ignoring cached content.",
        "clearCache": "Clear the browser cache and reload the page.",
        "clearCookies": "Clear this site’s cookies and reload the page.",
        "toggleDeveloperMode": "Show the full URL and developer tools for this site.",
        "resetZoom": "Return the page to its actual size.",
        "zoomIn": "Make the page larger.",
        "zoomOut": "Make the page smaller.",
        "viewSource": "Show the page’s source.",
        "devTools": "Open the developer tools.",
        "inspectElement": "Open the developer tools on the Elements panel.",
        "jsConsole": "Open the developer tools on the Console panel.",
        "pictureInPicture": "Pop the playing video out into a floating window.",
        "addSplitView": "Open another page beside this one.",
        "closeSplitPane": "Close the focused split pane.",
        "separateFromSplit": "Move the page out of the split view into its own tab.",
        "expandSplitPane": "Give the focused split pane the window, leaving the other panes narrow.",
        "flipSplitOrientation": "Switch the split view between side by side and stacked.",
        "nextSplitPane": "Focus the next split pane.",
        "previousSplitPane": "Focus the previous split pane.",
        "nextSpace": "Switch to the next space.",
        "previousSpace": "Switch to the previous space.",
        "editSpace": "Change the space’s name, emoji and theme.",
        "changeProfile": "Pick the profile the space’s sign-ins, cookies and extensions come from.",
        "deleteSpace": "Delete the current space.",
        "manageSpaces": "Open the Library’s Spaces page: every space side by side, to reorder or edit them.",
        "pinTab": "Pin the tab or unpin it.",
        "nextTab": "Switch to the next tab.",
        "previousTab": "Switch to the previous tab.",
        "recentTab": "Open the tab switcher and cycle through recent tabs, like ⌘Tab for apps.",
        "recentTabBackward": "Cycle backwards through recent tabs in the tab switcher.",
        "clearToday": "Archive all of today’s tabs.",
        "favoriteTab": "Add the tab to the favorites grid.",
        "renameTab": "Give the tab a name of your own.",
        "duplicateTab": "Open a copy of the tab.",
        "resetTab": "Return a pinned tab to its original URL.",
        "muteTab": "Mute or unmute the tab.",
        "goBack": "Go back a page.",
        "goForward": "Go forward a page.",
        "viewArchive": "Open the archive of closed tabs.",
        "openLibrary": "Open the Library.",
        "viewDownloads": "Show your downloads.",
        "promoteLittleWindow": "Move the Little Window’s or Peek’s page into the space its Open in button names.",
        "closeLittleWindows": "Close all Little Windows.",
        "settings": "Open Settings.",
        "setDefaultBrowser": "Make Cra the default browser.",
        "importData": "Bring tabs, spaces and extensions over from Arc or Dia.",
        "rebuildArcProfiles": "Put spaces imported from Arc back on their Arc profiles, with their sign-ins and extensions.",
        "clearBrowsingData": "Delete history, cookies and cached files with Chrome’s dialog.",
        "languageSettings": "Choose the languages websites show their pages in, for this space’s profile.",
        "checkForUpdates": "Look for a newer version of Cra.",
    ]
}
