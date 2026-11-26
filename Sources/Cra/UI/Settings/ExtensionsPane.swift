import AppKit
import SwiftUI

/// Installed unpacked extensions in Dia's card idiom, with the add/manage buttons under the
/// card the way Dia places "Advanced Settings" under its Privacy card, then the Live Folder plugins.
struct ExtensionsPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    // The app's one store: a share made here reaches the toolbar and Chrome at once (discussion #595).
    @State private var extensions = ExtensionStore.shared
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
                            // Which profiles have it, which Settings didn't say (discussion #595).
                            Text(profilesLine(e)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } trailing: {
                        if extensions.shares.isShared(e.extensionID) {
                            profilesMenu(e)
                            Button("Remove…") { confirmRemoveShared(e) }
                        } else if e.managedByChrome {
                            if e.fromWebStore && ExtensionStore.canShare { Button("Share…") { confirmShare(e) } }
                            removeFromProfile(e)
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
        .onAppear { extensions.reload() }
    }

    // MARK: Shared extensions (discussion #595)

    /// Profile folders, Default first, with the names Cra shows for them.
    private var profiles: [(folder: String, name: String)] {
        [("Default", store.profileName(nil))] + store.profiles.map { ($0.directoryName, $0.name) }
    }

    private func profilesLine(_ e: ExtensionStore.Entry) -> String { extensions.profilesLine(for: e, profiles: profiles) }

    /// A Web Store install's Remove…: its chrome://extensions page in the profile that has it, not the space Settings
    /// came from; installed separately in several profiles, a menu names them (#842).
    @ViewBuilder private func removeFromProfile(_ e: ExtensionStore.Entry) -> some View {
        let folders = ExtensionRemoval.pageProfiles(installedIn: e.profiles, allProfiles: profiles.map(\.folder))
        let open = { (folder: String) in
            actions.openProfilePage("chrome://extensions/?id=\(e.extensionID)", store.profiles.first { $0.directoryName == folder }?.id)
        }
        if folders.count > 1 {
            Menu("Remove…") {
                ForEach(profiles.filter { folders.contains($0.folder) }, id: \.folder) { p in
                    Button("From \(p.name)…") { open(p.folder) }
                }
            }
            .fixedSize()
        } else {
            Button("Remove…") { folders.first.map(open) ?? actions.openURL("chrome://extensions/?id=\(e.extensionID)") }
        }
    }

    /// A checkmark for each profile the shared extension belongs in; the last one can't be taken out (that is Remove).
    private func profilesMenu(_ e: ExtensionStore.Entry) -> some View {
        let folders = profiles.map(\.folder)
        let shares = extensions.shares
        return Menu("Profiles") {
            ForEach(profiles, id: \.folder) { p in
                let included = shares.profiles(of: e.extensionID, allProfiles: folders).contains(p.folder)
                Toggle(p.name, isOn: Binding(get: { included }, set: { on in
                    if on { extensions.setShared(e, profile: p.folder, included: true) } else { confirmExclude(e, profile: p) }
                }))
                .disabled(included && !shares.canExclude(e.extensionID, profile: p.folder, allProfiles: folders))
            }
            Divider()
            Button("Stop Sharing") { extensions.stopSharing(e) }
        }
        .fixedSize()
    }

    private func confirmShare(_ e: ExtensionStore.Entry) {
        guard let window = AppDialog.parentWindow else { return }
        AppDialog(title: "Share “\(e.name)” with every profile?",
                  message: "Cra installs it from the Chrome Web Store in each of your profiles, and in profiles you make later. "
                    + "Each profile keeps its own settings for it.\n\nChrome’s extension manager then shows it as managed by Cra: "
                    + "choose its profiles or remove it here, in Settings.",
                  actions: [DialogAction("Share"), .cancel]).present(over: window) { response in
            if response == .alertFirstButtonReturn { extensions.share(e) }
        }
    }

    private func confirmExclude(_ e: ExtensionStore.Entry, profile: (folder: String, name: String)) {
        guard let window = AppDialog.parentWindow else { return }
        AppDialog(title: "Remove “\(e.name)” from \(profile.name)?",
                  message: "It will be removed from that profile, with its data there. Its other profiles keep it.",
                  actions: [DialogAction("Remove", role: .destructive), .cancel]).present(over: window) { response in
            if response == .alertFirstButtonReturn { extensions.setShared(e, profile: profile.folder, included: false) }
        }
    }

    private func confirmRemoveShared(_ e: ExtensionStore.Entry) {
        guard let window = AppDialog.parentWindow else { return }
        AppDialog(title: "Remove “\(e.name)”?",
                  message: ExtensionRemoval.message(isShared: true, isCraCopy: false, profileCount: e.profiles?.count),
                  actions: [DialogAction("Remove", role: .destructive), .cancel]).present(over: window) { response in
            if response == .alertFirstButtonReturn { extensions.removeShared(e) }
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
