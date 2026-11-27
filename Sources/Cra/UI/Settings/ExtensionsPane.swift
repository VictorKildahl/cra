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

    /// The extension "Share across Profiles…" is open for, and the profile it was set up in.
    @State private var sharing: (entry: ExtensionStore.Entry, home: String)?

    var body: some View {
        SettingsCardPane {
            if extensions.entries.isEmpty {
                SettingsHeader("Installed extensions")
                SettingsCard {
                    SettingsCardRow {
                        Text("No extensions installed. Add one from the Chrome Web Store, or an unpacked extension folder (the kind Chrome’s “Load unpacked” takes).")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } trailing: { EmptyView() }
                }
            }
            // Shared across Profiles, then each profile's own, then Cra's own copies (discussion #595's follow-up).
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                SettingsHeader(section.title)
                SettingsCard {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { SettingsCardDivider() }
                        if let e = extensions.entries.first(where: { $0.extensionID == row.id }) {
                            extensionRow(e, section: section.kind, profile: row.profile)
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
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                ShareAcrossProfilesSheet(entry: sharing.entry, home: sharing.home, profiles: profiles) { picked in
                    self.sharing = nil
                    if let picked { confirmShare(sharing.entry, home: sharing.home, profiles: picked) }
                }
            }
        }
    }

    private var sections: [ExtensionsLayout.Section] {
        ExtensionsLayout.sections(
            items: extensions.entries.map {
                ExtensionsLayout.Item(id: $0.extensionID, name: $0.name, installedByChrome: $0.managedByChrome, profiles: $0.profiles)
            },
            shares: extensions.shares, allProfiles: profiles.map(\.folder), names: names)
    }

    private var names: [String: String] { Dictionary(profiles.map { ($0.folder, $0.name) }, uniquingKeysWith: { a, _ in a }) }

    @ViewBuilder
    private func extensionRow(_ e: ExtensionStore.Entry, section: ExtensionsLayout.Kind, profile: String?) -> some View {
        SettingsCardRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.name) \(e.version)").font(.system(size: 13))
                if !e.description.isEmpty {
                    Text(e.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                switch section {
                case .shared:
                    Text(profilesLine(e)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let home = ExtensionsLayout.homeLine(e.extensionID, shares: extensions.shares, names: names) {
                        Text(home).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                case .craCopies:
                    // Which profiles load Cra's copy (discussion #595).
                    Text(profilesLine(e)).font(.system(size: 11)).foregroundStyle(.secondary)
                case .profile:
                    EmptyView()
                }
            }
        } trailing: {
            switch section {
            case .shared:
                if ExtensionStore.canShareData {
                    Toggle("Turn \(e.name) on or off in every profile it is shared with",
                           isOn: Binding(get: { extensions.shares.isOn(e.extensionID) }, set: { extensions.setSharedOn(e, $0) }))
                        .labelsHidden().toggleStyle(.arcSwitch)
                        .help("On or off in every profile it is shared with")
                }
                profilesMenu(e)
                Button("Remove…") { confirmRemoveShared(e) }
            case .profile(let folder):
                if e.fromWebStore && ExtensionStore.canShare {
                    Button(ExtensionStore.canShareData ? "Share across Profiles…" : "Share…") {
                        if ExtensionStore.canShareData { sharing = (e, folder) } else { confirmShare(e) }
                    }
                }
                Button("Remove…") { openRemovalPage(e, profile: folder) }
            case .craCopies:
                Button("Remove") { extensions.remove(e) }
            }
        }
    }

    /// chrome://extensions in the profile whose own install this is (#842), where its Remove removes it from that one.
    private func openRemovalPage(_ e: ExtensionStore.Entry, profile folder: String) {
        actions.openProfilePage("chrome://extensions/?id=\(e.extensionID)", store.profiles.first { $0.directoryName == folder }?.id)
    }

    // MARK: Shared extensions (discussion #595)

    /// Profile folders, Default first, with the names Cra shows for them.
    private var profiles: [(folder: String, name: String)] {
        [("Default", store.profileName(nil))] + store.profiles.map { ($0.directoryName, $0.name) }
    }

    private func profilesLine(_ e: ExtensionStore.Entry) -> String { extensions.profilesLine(for: e, profiles: profiles) }

    /// A checkmark for each profile the shared extension belongs in; the last one can't be taken out (that is Remove).
    private func profilesMenu(_ e: ExtensionStore.Entry) -> some View {
        let folders = profiles.map(\.folder)
        let shares = extensions.shares
        let home = shares.home(of: e.extensionID)
        let canStop = home == nil || shares.canStopSharing(e.extensionID, allProfiles: folders)
        return Menu("Profiles") {
            ForEach(profiles, id: \.folder) { p in
                let included = shares.profiles(of: e.extensionID, allProfiles: folders).contains(p.folder)
                Toggle(p.folder == home ? "\(p.name) (its settings)" : p.name, isOn: Binding(get: { included }, set: { on in
                    if on { confirmInclude(e, profile: p) } else { confirmExclude(e, profile: p) }
                }))
                .disabled(included && !shares.canExclude(e.extensionID, profile: p.folder, allProfiles: folders))
            }
            Divider()
            // With one profile's data, sharing stops once that profile is the only one left: it keeps its own.
            Button(canStop ? "Stop Sharing" : "Stop Sharing (uncheck the other profiles first)") { extensions.stopSharing(e) }
                .disabled(!canStop)
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

    /// "Share across Profiles…" picked `picked`: a profile that has its own install already is asked about first,
    /// because it uses `home`'s settings and sign-in for it from now on.
    private func confirmShare(_ e: ExtensionStore.Entry, home: String, profiles picked: [String]) {
        let replaced = SharedExtensions.replacedInstalls(home: home, profiles: picked, installedIn: e.profiles ?? [])
        guard !replaced.isEmpty, let window = AppDialog.parentWindow else {
            extensions.share(e, from: home, with: picked)
            return
        }
        let homeName = names[home] ?? home
        let list = replaced.map { names[$0] ?? $0 }
        AppDialog(title: "Use \(homeName)’s “\(e.name)” in \(Self.joined(list))?",
                  message: "\(Self.joined(list)) \(list.count == 1 ? "has" : "have") “\(e.name)” already, with \(list.count == 1 ? "its" : "their") own "
                    + "settings and sign-in. While it’s shared, \(list.count == 1 ? "it uses" : "they use") \(homeName)’s instead. "
                    + "Websites’ cookies and logins stay each profile’s own.",
                  actions: [DialogAction("Share"), .cancel]).present(over: window) { response in
            if response == .alertFirstButtonReturn { extensions.share(e, from: home, with: picked) }
        }
    }

    /// A profile's checkmark put back under a shared extension. One with its own install is asked about, as in Share.
    private func confirmInclude(_ e: ExtensionStore.Entry, profile: (folder: String, name: String)) {
        guard let home = extensions.shares.home(of: e.extensionID), e.profiles?.contains(profile.folder) == true,
              let window = AppDialog.parentWindow else {
            extensions.setShared(e, profile: profile.folder, included: true)
            return
        }
        let homeName = names[home] ?? home
        AppDialog(title: "Use \(homeName)’s “\(e.name)” in \(profile.name)?",
                  message: "\(profile.name) has “\(e.name)” already, with its own settings and sign-in. While it’s shared, it uses "
                    + "\(homeName)’s instead.",
                  actions: [DialogAction("Share"), .cancel]).present(over: window) { response in
            if response == .alertFirstButtonReturn { extensions.setShared(e, profile: profile.folder, included: true) }
        }
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
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
