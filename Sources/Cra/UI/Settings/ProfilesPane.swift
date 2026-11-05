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
    @State private var editingEmail: SignupEmailProfile?

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
        .sheet(item: $editingEmail) { profile in
            SignupEmailEditor(profile: profile)
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
            HStack(spacing: 6) {
                Button("Signup email…") {
                    editingEmail = SignupEmailProfile(name: name, path: store.profilePath(profile: profileID))
                }
                .accessibilityLabel("Signup email for \(name)")
                trailing()
            }
        }
    }
}

private struct SignupEmailProfile: Identifiable {
    let name: String
    let path: String?
    var id: String { path ?? "Default" }
}

private struct SignupEmailEditor: View {
    let profile: SignupEmailProfile
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var failed = false

    init(profile: SignupEmailProfile) {
        self.profile = profile
        _email = State(initialValue: SignupEmailPreferences.address(profilePath: profile.path) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signup email for \(profile.name)").font(.headline)
            SignupEmailDraftField(email: $email, title: "Email address",
                                  detail: "Clear the address to turn off signup suggestions for this profile.",
                                  saveFailed: failed)
                .onChange(of: email) { _, _ in failed = false }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try SignupEmailPreferences.set(email, profilePath: profile.path)
                        dismiss()
                    } catch { failed = true }
                }
                .disabled(!email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && SignupEmail.address(email) == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// A draft only becomes a profile preference when its enclosing screen is confirmed.
struct SignupEmailDraftField: View {
    @Binding var email: String
    let title: String
    let detail: String
    let saveFailed: Bool
    var showsPreview = true

    var body: some View {
        let address = SignupEmail.address(email)
        let invalid = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && address == nil
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .accessibilityLabel(title)
                .autocorrectionDisabled()
            if invalid || saveFailed {
                Text(invalid ? "Enter a complete email address, or leave it blank." : "Couldn’t save this email. Try again.")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if showsPreview && !invalid {
                SignupEmailPreview(address: address ?? "you@example.com")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
