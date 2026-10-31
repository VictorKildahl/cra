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
                Picker("", selection: $store.settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                SettingsCheckbox(title: "Show search suggestions", isOn: $store.settings.searchSuggestions)
            }
            SettingsFormRow(label: "When quitting Cra:") {
                SettingsCheckbox(title: "Warn before quitting", isOn: $store.settings.warnBeforeQuitting)
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
