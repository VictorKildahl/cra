import SwiftUI

/// The profile picked for a space: Default (nil), an existing one, or a new one to make.
enum SpaceProfileChoice: Hashable {
    case existing(UUID?)
    case new
}

/// Create or edit a space: name, emoji, colors, intensity, grain, appearance, profile
/// (Arc: SpaceCreation + SpaceStyleEditor + SpaceIconPicker + "Edit Space profile").
struct SpaceEditorView: View {
    let existing: Space?
    let profiles: [BrowserProfile]
    /// Title, emoji, theme, profile; a new profile comes with its name.
    let onSave: (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var emoji: String
    @State private var theme: SpaceTheme
    @State private var color1: Color
    @State private var color2: Color
    @State private var profile: SpaceProfileChoice
    @State private var newProfileName = ""

    private static let emojis = ["🌱", "💼", "🏠", "🎨", "🧪", "📚", "🎮", "🎵", "🛒", "✈️", "💡", "🔥", "🌊", "🍕", "🐦", "🧑‍💻",
                                 "📈", "🧠", "❤️", "⭐️", "🌙", "☕️", "🏃", "📷", "🎬", "🧩", "🪴", "🏔️", "🛠️", "💰", "📝", "🎯"]

    /// `initialProfile` is a new space's starting profile (Arc: the focused space's).
    init(existing: Space?, profiles: [BrowserProfile], initialProfile: UUID? = nil,
         onSave: @escaping (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.profiles = profiles
        _profile = State(initialValue: .existing(existing == nil ? initialProfile : existing?.profileID))
        self.onSave = onSave
        self.onCancel = onCancel
        let t = existing?.theme ?? SpaceTheme.presets[Int.random(in: 0..<5)]
        _title = State(initialValue: existing?.title ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🌱")
        _theme = State(initialValue: t)
        _color1 = State(initialValue: Color(hex: t.colors.first ?? "#CCCCCC"))
        _color2 = State(initialValue: Color(hex: t.colors.count > 1 ? t.colors[1] : (t.colors.first ?? "#CCCCCC")))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(existing == nil ? "New Space" : "Edit Space").font(.system(size: 16, weight: .semibold))
            HStack(spacing: 12) {
                // Preview
                ZStack {
                    SpaceBackground(palette: theme.palette)
                    VStack(spacing: 6) {
                        Text(emoji).font(.system(size: 28))
                        Text(title.isEmpty ? "Space" : title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                        RoundedRectangle(cornerRadius: 6).fill(theme.palette.selectedFill).frame(width: 100, height: 22)
                        RoundedRectangle(cornerRadius: 6).fill(theme.palette.hoverFill).frame(width: 100, height: 22)
                    }
                }
                .frame(width: 180, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
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
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(SpaceTheme.presets.indices, id: \.self) { i in
                        let p = SpaceTheme.presets[i]
                        Circle().fill(p.palette.gradient).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                            .onTapGesture {
                                theme = p
                                color1 = Color(hex: p.colors[0]); color2 = Color(hex: p.colors[1])
                            }
                    }
                    Spacer()
                    ColorPicker("", selection: $color1, supportsOpacity: false).labelsHidden()
                    ColorPicker("", selection: $color2, supportsOpacity: false).labelsHidden()
                }
                HStack {
                    Text("Intensity").frame(width: 70, alignment: .leading)
                    Slider(value: $theme.intensity, in: 0...1)
                }
                HStack {
                    Text("Grain").frame(width: 70, alignment: .leading)
                    Slider(value: $theme.noise, in: 0...1)
                }
                Picker("Appearance", selection: $theme.appearance) {
                    Text("Auto").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Divider()
            profileSection
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
        .frame(width: 520)
        .onChange(of: color1) { _, c in theme.colors = [c.hexString, color2.hexString] }
        .onChange(of: color2) { _, c in theme.colors = [color1.hexString, c.hexString] }
    }

    private var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespaces) }

    /// Arc's copy: "Profiles make your Spaces truly separate…" and, when an existing space
    /// changes profile, "Each Profile has different browser data…".
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Profile", selection: $profile) {
                    Text("Default").tag(SpaceProfileChoice.existing(nil))
                    ForEach(profiles) { p in Text(p.name).tag(SpaceProfileChoice.existing(p.id)) }
                    Divider()
                    Text("New Profile…").tag(SpaceProfileChoice.new)
                }
                .frame(width: 260)
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
