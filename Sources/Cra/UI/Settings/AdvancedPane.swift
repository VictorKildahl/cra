import CraCEF
import SwiftUI

/// Dia's Advanced pane is a form: "General:" (Automatically update), "Sounds:", "Address Bar:"
/// (a routing popup) and "When quitting Dia:" (Warn before quitting + a restore popup). Cra
/// has no chat sounds; its page engine, search engine, import and version rows live here
/// instead.
struct AdvancedPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = SoftwareUpdater.shared
        SettingsFormPane {
            SettingsFormRow(label: "General:") {
                SettingsCheckbox(title: "Automatically update Cra", isOn: $updater.automaticallyUpdates)
                    .disabled(!updater.isAvailable)
                HStack(spacing: 8) {
                    Button("Check for Updates…") { updater.checkForUpdates(nil) }
                        .disabled(!updater.isAvailable)
                    Text(updater.lastCheckSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                SettingsCheckbox(title: "Chrome engine for pages (extensions, Chrome DevTools)", isOn: $store.settings.chromeEngine)
                Text("Restart Cra to apply an engine change.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsFormRow(label: "Address Bar:") {
                SearchEnginePicker(store: store, openURL: actions.openURL)
                SettingsCheckbox(title: "Show search suggestions", isOn: $store.settings.searchSuggestions)
            }
            SettingsFormRow(label: "Sounds:") {
                // Arc: Settings ▸ Advanced "Play Arc sound effects".
                SettingsCheckbox(title: "Play Cra sound effects", isOn: $store.settings.soundEffects)
            }
            SettingsFormRow(label: "Websites:") {
                // Arc: Settings ▸ Advanced "Allow websites to get your theme data" (--arc-palette-* variables).
                SettingsCheckbox(title: "Allow websites to get your theme data", isOn: $store.settings.shareThemeWithWebsites)
                // Arc: "Allow window dragging from the top of webpages" (with the toolbar hidden).
                SettingsCheckbox(title: "Allow window dragging from the top of webpages", isOn: $store.settings.pageTopWindowDrag)
            }
            SettingsFormRow(label: "When quitting Cra:") {
                SettingsCheckbox(title: "Warn before quitting", isOn: $store.settings.warnBeforeQuitting)
                // Arc: Settings ▸ Advanced "When opening Arc, restore windows from previous session".
                SettingsCheckbox(title: "When opening Cra, restore windows from previous session", isOn: $store.settings.restoreWindows)
            }
            SettingsFormRow(label: "Import:") {
                Button("Import from Another Browser…") { actions.importData() }
                let names = ImportSource.allCases.filter { $0.kind != .safari && $0.isAvailable }.map(\.name)
                Text(names.isEmpty
                     ? "Bring bookmarks, open tabs, passwords and sign-ins over from Safari."
                     : "Bring spaces, tabs, folders, favorites, passwords, sign-ins and extensions over from \(names.joined(separator: ", ")), Safari and more.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsFormRow(label: "Export:") {
                Button("Export Spaces and Pinned Tabs…") { SidebarExport.run(store, in: NSApp.keyWindow) }
                Text("Save every space's favorites, pinned tabs and folders as a bookmarks file that Chrome, Safari, Firefox and other browsers can import.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsFormRow(label: "About:") {
                Text("Cra \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").font(.system(size: 13))
                Text("Chromium \(CraCEFRuntime.chromiumVersion()) · CEF \(CraCEFRuntime.cefVersion())")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(AppPaths.supportDir.path).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Chromium's default search engine, the one chrome://settings/searchEngines sets (Arc: Settings ▸
/// Profiles ▸ Default Search Engine, beside "Search Settings"): its built-in engines and whichever is
/// the default. The page adds, edits and removes the rest.
private struct SearchEnginePicker: View {
    let store: SidebarStore
    let openURL: (String) -> Void
    @State private var engines: [ChromiumSearchEngine] = []
    @State private var selected = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { selected }, set: pick)) {
                ForEach(engines, id: \.keyword) { Text($0.name).tag($0.keyword) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Manage Search Engines…") { openURL(SearchEngines.settingsPage) }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let current = SearchEngines.shared.defaultEngine(profilePath: nil, legacy: store.settings.searchEngine)
        var list = SearchEngines.shared.keywords(profilePath: nil).filter(\.isBuiltIn)
        if !list.contains(where: { $0.keyword == current.keyword }) { list.insert(current, at: 0) }
        engines = list
        selected = current.keyword
    }

    private func pick(_ keyword: String) {
        guard let engine = engines.first(where: { $0.keyword == keyword }) else { return }
        SearchEngines.shared.setDefault(engine, store: store)
        selected = keyword
    }
}
