import AppKit
import SwiftUI

/// Dia's Shortcuts pane: a search field with filter and more buttons, a 272 pt list card of
/// actions grouped under their menu titles (36 pt rows, shortcut right-aligned), and a detail
/// column with the action's title, description and a black full-width shortcut field.
struct ShortcutsPane: View {
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var query = ""
    @State private var selectedID: String?
    @State private var customizedOnly = false
    @State private var conflictingOnly = false

    /// Dia's selected shortcut row (sampled 95,144,229 in dark mode; it is not the accent colour).
    private static let selectionFill = Color(.sRGB, red: 95 / 255, green: 144 / 255, blue: 229 / 255, opacity: 1)
    private static let listWidth: CGFloat = 272
    private static let rowHeight: CGFloat = 36
    private static let sections: [(MenuSection, String)] = [
        (.app, "Cra"), (.file, "File"), (.edit, "Edit"), (.view, "View"), (.spaces, "Spaces"),
        (.tabs, "Tabs"), (.archive, "Archive"), (.window, "Window"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SettingsSearchField(text: $query)
                    .frame(height: 26)
                Menu {
                    Toggle("Customized Shortcuts", isOn: $customizedOnly)
                    Toggle("Conflicting Shortcuts", isOn: $conflictingOnly)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 26, height: 26)
                Menu {
                    Button("Reset All Shortcuts") { bindings.resetOverrides() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 19)
            .padding(.top, 19)
            HStack(alignment: .top, spacing: 15) {
                list
                detail
            }
            .padding(.leading, 19)
            .padding(.trailing, 20.5)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: List

    private var visible: [(title: String, actions: [KeyAction])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.sections.compactMap { section, title in
            let acts = bindings.actions(in: section).filter { a in
                (q.isEmpty || a.name.lowercased().contains(q))
                    && (!customizedOnly || bindings.isOverridden(a.id))
                    && (!conflictingOnly || !conflicts(of: a).isEmpty)
            }
            return acts.isEmpty ? nil : (title, acts)
        }
    }

    private func conflicts(of a: KeyAction) -> [KeyAction] {
        guard let s = a.primary else { return [] }
        return bindings.actions.filter { $0.id != a.id && $0.shortcuts.contains(s) }
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(visible, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .bottomLeading)
                        .padding(.bottom, 4)
                    ForEach(group.actions) { a in
                        SettingsCardDivider()
                        row(a)
                    }
                }
            }
        }
        .frame(width: Self.listWidth)
        .frame(maxHeight: .infinity)
        // Dia's list card is the window colour with a 1 pt white-6% outline (not the filled card).
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func row(_ a: KeyAction) -> some View {
        let selected = a.id == selectedID
        return Button { selectedID = a.id } label: {
            HStack(spacing: 8) {
                Text(a.name).font(.system(size: 13)).foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 8)
                Text(a.shortcuts.map(\.display).joined(separator: "  "))
                    .font(.system(size: 13)).foregroundStyle(selected ? Color.white : Color.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(selected ? Self.selectionFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let a = selectedID.flatMap({ bindings.action($0) }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(a.name).font(.system(size: 22, weight: .bold))
                    Spacer()
                    Menu {
                        Button("Reset to Default") { bindings.resetShortcuts(for: a.id) }.disabled(!bindings.isOverridden(a.id))
                        Button("Remove Shortcut") { bindings.setShortcuts([], for: a.id) }.disabled(a.shortcuts.isEmpty)
                    } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                Text(ShortcutDescriptions.text(for: a))
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ShortcutRecorder(action: a)
                let c = conflicts(of: a)
                if !c.isEmpty {
                    Text((c.count == 1 ? "This shortcut conflicts with another shortcut: " : "This shortcut conflicts with other shortcuts: ")
                         + c.map(\.name).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Perform common actions in Cra faster and from anywhere.")
                Text("Select an action to customize its keyboard shortcut.")
            }
            .font(.system(size: 15)).foregroundStyle(.secondary)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Dia's shortcut field: a black 29 pt capsule-cornered bar showing the keys, 15 pt white.
/// Click it, then press the new keys; Esc cancels, ⌫ removes the shortcut.
struct ShortcutRecorder: View {
    let action: KeyAction
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (action.shortcuts.isEmpty ? "None" : action.shortcuts.map(\.display).joined(separator: "  ")))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(recording ? Color.accentColor : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 29)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(recording ? Color.accentColor : Color.clear))
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

/// NSSearchField, so the field matches Dia's standard search field.
struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.placeholderString = "Search"
        f.delegate = context.coordinator
        f.controlSize = .regular
        f.font = .systemFont(ofSize: 13)
        return f
    }

    func updateNSView(_ v: NSSearchField, context: Context) {
        if v.stringValue != text { v.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSSearchField else { return }
            text.wrappedValue = f.stringValue
        }
    }
}

/// One-line descriptions for the detail column (Dia: "Create a new tab.").
enum ShortcutDescriptions {
    static func text(for a: KeyAction) -> String {
        if let t = table[a.id] { return t }
        if a.id.hasPrefix("item"), let n = a.id.dropFirst(4).first { return "Switch to the \(n). tab in the sidebar." }
        if a.id.hasPrefix("space"), let n = a.id.dropFirst(5).first { return "Switch to the \(n). space." }
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
        "newGitHubLiveFolder": "Add a folder that fills itself with your open pull requests and review requests.",
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
        "flipSplitOrientation": "Switch the split view between side by side and stacked.",
        "nextSplitPane": "Focus the next split pane.",
        "previousSplitPane": "Focus the previous split pane.",
        "nextSpace": "Switch to the next space.",
        "previousSpace": "Switch to the previous space.",
        "editSpace": "Change the space’s name, emoji and theme.",
        "deleteSpace": "Delete the current space.",
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
        "promoteLittleWindow": "Move the Little Window’s page into a space.",
        "closeLittleWindows": "Close all Little Windows.",
        "settings": "Open Settings.",
        "setDefaultBrowser": "Make Cra the default browser.",
        "importData": "Bring tabs, spaces and extensions over from Arc or Dia.",
    ]
}
