import AppKit
import SwiftUI

/// Installed unpacked extensions in Dia's card idiom, with the add/manage buttons under the
/// card the way Dia places "Advanced Settings" under its Privacy card, then the Live Folder plugins.
struct ExtensionsPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    @State private var extensions = ExtensionStore()
    @State private var error: String?

    var body: some View {
        SettingsCardPane {
            SettingsHeader("Installed extensions")
            SettingsCard {
                if extensions.entries.isEmpty {
                    SettingsCardRow {
                        Text("No extensions installed. Add one from the Chrome Web Store, or an unpacked extension folder (the kind Chrome’s “Load unpacked” takes).")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } trailing: { EmptyView() }
                }
                ForEach(Array(extensions.entries.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { SettingsCardDivider() }
                    SettingsCardRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(e.name) \(e.version)").font(.system(size: 13))
                            if !e.description.isEmpty {
                                Text(e.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    } trailing: {
                        if e.managedByChrome {
                            Button("Remove…") { actions.openURL("chrome://extensions/?id=\(e.extensionID)") }
                        } else {
                            Button("Remove") { extensions.remove(e) }
                        }
                    }
                }
            }
            HStack {
                Button("Add Unpacked Extension…") { addExtension() }
                Spacer()
                Button("Open Chrome’s Extension Manager") { actions.openURL("chrome://extensions") }
                    .disabled(!store.settings.chromeEngine)
            }
            .padding(.top, 7.5)
            if let error { SettingsFootnote(error).foregroundStyle(.red) }
            SettingsFootnote(store.settings.chromeEngine
                             ? (extensions.needsRestart ? "Restart Cra to apply the change." : "Extensions load when Cra starts.")
                             : "Extensions need the Chrome engine (Advanced tab).")
            // Live Folder plugins have no Arc tab either: they sit under the extensions.
            PluginsPane().settingsNested().padding(.top, 20)
        }
    }

    private func addExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose an unpacked extension folder (it holds manifest.json)."
        if panel.runModal() == .OK, let url = panel.url {
            do { try extensions.add(folder: url); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}
