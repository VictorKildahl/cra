import SwiftUI

/// Dia's Profiles pane (and Arc's Profiles preferences): the profiles and how many spaces
/// use each, "Create Profile…" under the card. A space picks its profile in Edit Space.
/// Arc only deletes profiles no space uses, and never Default.
struct ProfilesPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    @State private var naming: BrowserProfile?
    @State private var name = ""
    @State private var deleting: BrowserProfile?

    var body: some View {
        SettingsCardPane {
            SettingsHeader("Profiles")
            SettingsCard {
                row(name: "Default", profileID: nil) { EmptyView() }
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    row(name: p.name, profileID: p.id) {
                        Button("Rename…") { name = p.name; naming = p }
                        Button("Delete…") { deleting = p }
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
        }
        .alert("Rename Profile", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Profile name", text: $name)
            Button("Rename") { if let p = naming { store.renameProfile(p.id, to: trimmed) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let p = deleting { store.deleteProfile(p.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.")
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

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
