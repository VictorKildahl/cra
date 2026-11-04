import SwiftUI

/// The profile picked for a space: Default (nil), an existing one, or a new one to make.
enum SpaceProfileChoice: Hashable {
    case existing(UUID?)
    case new
}

/// Create or edit a space: name, emoji, profile and, beside them, Arc's theme editor (the same
/// card Edit Theme Color… opens: pad, presets, intensity, grain, Auto / Light / Dark). An existing
/// space shows each change at once (`onPreview`); Cancel puts its theme back, Save writes it.
struct SpaceEditorView: View {
    let existing: Space?
    let profiles: [BrowserProfile]
    /// Title, emoji, theme, profile; a new profile comes with its name.
    let onSave: (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void
    let onCancel: () -> Void
    let onPreview: (SpaceTheme) -> Void

    @State private var title: String
    @State private var emoji: String
    @State private var theme: SpaceTheme
    @State private var profile: SpaceProfileChoice
    @State private var newProfileName = ""

    private static let emojis = ["🌱", "💼", "🏠", "🎨", "🧪", "📚", "🎮", "🎵", "🛒", "✈️", "💡", "🔥", "🌊", "🍕", "🐦", "🧑‍💻",
                                 "📈", "🧠", "❤️", "⭐️", "🌙", "☕️", "🏃", "📷", "🎬", "🧩", "🪴", "🏔️", "🛠️", "💰", "📝", "🎯"]

    /// `initialProfile` is a new space's starting profile (Arc: the focused space's).
    init(existing: Space?, profiles: [BrowserProfile], initialProfile: UUID? = nil,
         onSave: @escaping (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void, onCancel: @escaping () -> Void,
         onPreview: @escaping (SpaceTheme) -> Void = { _ in }) {
        self.existing = existing
        self.profiles = profiles
        _profile = State(initialValue: .existing(existing == nil ? initialProfile : existing?.profileID))
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPreview = onPreview
        _title = State(initialValue: existing?.title ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🌱")
        _theme = State(initialValue: existing?.theme ?? SpaceColorPresets.newSpaceTheme())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(existing == nil ? "New Space" : "Edit Space").font(.system(size: 16, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    TextField("Name", text: $title).textFieldStyle(.roundedBorder)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Text(e).font(.system(size: 16)).frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(e == emoji ? Color.accentColor.opacity(0.25) : .clear))
                                .onTapGesture { emoji = e }
                        }
                    }
                    HStack {
                        Text("Custom emoji").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("", text: $emoji).textFieldStyle(.roundedBorder).frame(width: 50)
                            .onChange(of: emoji) { _, v in if v.count > 2 { emoji = String(v.suffix(2)) } }
                    }
                    Divider()
                    profileSection
                    Spacer(minLength: 0)
                }
                .frame(width: 260)
                SpaceStyleEditor(theme: theme) { t in
                    theme = t
                    onPreview(t)
                }
            }
            HStack {
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Create Space" : "Save") {
                    onSave(title.isEmpty ? "Space" : title, emoji.isEmpty ? "🌱" : emoji, theme, profile, trimmedProfileName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled((title.trimmingCharacters(in: .whitespaces).isEmpty && existing == nil) || (profile == .new && trimmedProfileName.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 651)
    }

    /// The space as the sidebar draws it, with the theme being edited.
    private var preview: some View {
        ZStack {
            SpaceBackground(palette: theme.palette)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(emoji).font(.system(size: 15))
                    Text(title.isEmpty ? "Space" : title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 6).fill(theme.palette.selectedFill).frame(height: 24)
                RoundedRectangle(cornerRadius: 6).fill(theme.palette.hoverFill).frame(height: 24)
            }
            .padding(12)
        }
        .frame(width: 260, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespaces) }

    /// Arc's copy: "Profiles make your Spaces truly separate…" and, when an existing space
    /// changes profile, "Each Profile has different browser data…".
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Profile", selection: $profile) {
                    Text("Default").tag(SpaceProfileChoice.existing(nil))
                    ForEach(profiles) { p in Text(p.name).tag(SpaceProfileChoice.existing(p.id)) }
                    Divider()
                    Text("New Profile…").tag(SpaceProfileChoice.new)
                }
                if profile == .new {
                    TextField("Profile name", text: $newProfileName).textFieldStyle(.roundedBorder)
                }
            }
            Text(profileNote).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileNote: String {
        if let existing, profile != .existing(existing.profileID) {
            return "Each Profile has different browser data, so you might get logged out of some websites or need to re-install extensions. Open tabs in this space reload."
        }
        if profile == .new {
            return "This Space will start fresh in your brand new Profile, signed out of every website."
        }
        return "Profiles make your Spaces truly separate with their own logins, cookies and site data. Spaces with the same Profile share them."
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
    }
}
