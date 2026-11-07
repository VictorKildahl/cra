import AppKit
import CraCEF
import SwiftUI

/// Dia's Profiles pane (and Arc's Profiles preferences): the profiles and how many spaces
/// use each, "Create Profile…" under the card. A space picks its profile in Edit Space.
/// Arc only deletes profiles no space uses, and never Default.
struct ProfilesPane: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        SettingsCardPane {
            SettingsHeader("Profiles")
            SettingsCard {
                row(name: "Default", profileID: nil) { EmptyView() }
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    row(name: p.name, profileID: p.id) {
                        Button("Rename…") { rename(p) }
                        Button("Delete…") { delete(p) }
                            .disabled(!store.spaces(usingProfile: p.id).isEmpty)
                    }
                }
            }
            HStack {
                Button("Create Profile…") { actions.newProfile() }
                Spacer()
                // Spaces an Arc import left on Default, back on their Arc profiles (#131).
                if ArcProfileRebuilder.isAvailable {
                    Button("Rebuild from Arc…") { actions.rebuildArcProfiles() }
                        .help("Put spaces imported from Arc back on the profiles they use in Arc, with their sign-ins and extensions.")
                }
            }
            .padding(.top, 7.5)
            SettingsFootnote("Profiles help keep your data separate across Spaces, like logins, cookies and site data. You can use any Profile across one or more Spaces: choose Spaces ▸ Change Profile, or Set Profile on a Space's menu. Spaces on the same Profile share their logins. Only Profiles not assigned to any Spaces can be deleted.")
            // Arc's per-profile Download location (DownloadLocationView: the folder, Ask
            // Where to Save, Other…), GitHub #190.
            SettingsHeader("Downloads").padding(.top, 20)
            SettingsCard {
                downloadRow(name: "Default", profileID: nil)
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    downloadRow(name: p.name, profileID: p.id)
                }
            }
            SettingsFootnote("Where each Profile saves downloaded files. Choose Ask Where to Save Each File to pick a place every time.")
            // Chromium's per-profile website languages (#209); Arc leaves them to arc://settings/languages.
            SettingsHeader("Languages").padding(.top, 20)
            SettingsCard {
                languageRow(name: "Default", profileID: nil)
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    languageRow(name: p.name, profileID: p.id)
                }
            }
            .id(nav.shown)  // read again each time Settings comes up: Chromium's page may have changed them
            SettingsFootnote("The languages websites show their pages in for each Profile, most wanted first. Change opens Chromium’s language settings for that Profile. Cra itself stays in English.")
        }
    }

    private enum DownloadChoice: Hashable { case folder, ask, other }

    private func downloadRow(name: String, profileID: UUID?) -> some View {
        let location = store.settings.downloadLocation(profileID: profileID)
        let folder = DownloadDestinations.folder(profileID: profileID)
        let choice = Binding<DownloadChoice>(
            get: { location.askWhereToSave ? .ask : .folder },
            set: { picked in
                var l = store.settings.downloadLocation(profileID: profileID)
                switch picked {
                case .folder: l.askWhereToSave = false
                case .ask: l.askWhereToSave = true
                case .other:
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = folder
                    panel.prompt = "Select"
                    panel.message = "Choose where \(name) saves downloaded files."
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    l.folder = url.standardizedFileURL.path == DownloadDestinations.downloadsFolder.standardizedFileURL.path ? nil : url.path
                    l.askWhereToSave = false
                }
                store.settings.setDownloadLocation(l, profileID: profileID)
            })
        return SettingsCardRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13))
                Text("Download location").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } trailing: {
            Picker("Download location", selection: choice) {
                Label(FileManager.default.displayName(atPath: folder.path), systemImage: "folder").tag(DownloadChoice.folder)
                Text("Ask Where to Save Each File").tag(DownloadChoice.ask)
                Divider()
                Text("Other…").tag(DownloadChoice.other)
            }
            .labelsHidden()
            .frame(width: 200)
            .help(folder.path)
        }
    }

    private func languageRow(name: String, profileID: UUID?) -> some View {
        let summary = BrowserLanguages.summary(languages(profileID: profileID))
        let hasSpace = !store.spaces(usingProfile: profileID).isEmpty
        return SettingsCardRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13))
                Text(summary.isEmpty ? "Chromium’s default languages" : summary)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .help(summary)
            }
        } trailing: {
            Button("Change…") { actions.openProfilePage(BrowserLanguages.settingsPage, profileID) }
                .disabled(!hasSpace)
                .help(hasSpace ? "Open Chromium’s language settings for \(name)." : "Set \(name) on a Space first.")
        }
    }

    /// What Chromium holds for the profile now, else what its Preferences file saved (a profile no
    /// page has loaded in since launch).
    private func languages(profileID: UUID?) -> [String] {
        let path = store.profilePath(profile: profileID)
        if let json = CraCEFRuntime.preference(BrowserLanguages.pref, forProfile: path) {
            return BrowserLanguages.codes(json)
        }
        let folder = path.map { URL(fileURLWithPath: $0) } ?? AppPaths.chromiumCache.appendingPathComponent("Default")
        return (try? Data(contentsOf: folder.appendingPathComponent("Preferences")))
            .flatMap(BrowserLanguages.codes(preferencesFile:)) ?? []
    }

    private func rename(_ profile: BrowserProfile) {
        guard let window = AppDialog.parentWindow else { return }
        let dialog = AppDialog(title: "Rename your Profile",
                               message: "This won’t affect the names of any of the Spaces associated with this Profile.",
                               actions: [DialogAction("Save"), .cancel], input: profile.name, placeholder: "Profile name", requiresInput: true,
                               icon: .none, width: 496, buttonSpacing: 30, buttonOutset: 0)
        dialog.present(over: window) { response in
            guard response == .alertFirstButtonReturn, let name = dialog.input else { return }
            store.renameProfile(profile.id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func delete(_ profile: BrowserProfile) {
        guard let window = AppDialog.parentWindow else { return }
        let dialog = AppDialog(title: "Delete “\(profile.name)”?",
                               message: "Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.",
                               actions: [DialogAction("Delete Profile", role: .destructive), .cancel])
        dialog.present(over: window) { response in
            if response == .alertFirstButtonReturn { store.deleteProfile(profile.id) }
        }
    }

    private func row<Trailing: View>(name: String, profileID: UUID?, @ViewBuilder trailing: () -> Trailing) -> some View {
        let spaces = store.spaces(usingProfile: profileID)
        return SettingsCardRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13))
                Text(spaces.isEmpty ? "No Spaces" : spaces.map { "\($0.emoji) \($0.title)" }.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        } trailing: {
            HStack(spacing: 6) { trailing() }
        }
    }
}
