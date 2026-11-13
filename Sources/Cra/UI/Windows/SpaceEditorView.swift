import SwiftUI

/// The profile picked for a space: Default (nil), an existing one, or a new one to make.
enum SpaceProfileChoice: Hashable {
    case existing(UUID?)
    case new
}

/// Create or edit a space: name, icon, profile and, beside them, Arc's theme editor (the same
/// card Edit Theme Color… opens: pad, presets, intensity, grain, Auto / Light / Dark). An existing
/// space shows each change at once (`onPreview`); Cancel puts its theme back, Save writes it.
struct SpaceEditorView: View {
    let existing: Space?
    let profiles: [BrowserProfile]
    /// The Search Engine picker's rows (#306) and the name of the default it falls back to.
    let searchEngines: [ChromiumSearchEngine]
    let defaultEngineName: String
    /// Title, icon, theme, profile, a new profile's name, and the search engine's keyword (nil: default).
    let onSave: (String, SpaceIcon, SpaceTheme, SpaceProfileChoice, String, String?) -> Void
    let onCancel: () -> Void
    let onPreview: (SpaceTheme) -> Void

    @State private var title: String
    /// Saved as it is: an untouched symbol or empty icon stays what it was (#205).
    @State private var icon: SpaceIcon
    @State private var pickingIcon = false
    @State private var theme: SpaceTheme
    @State private var profile: SpaceProfileChoice
    @State private var newProfileName = ""
    /// The engine's keyword; empty is the default.
    @State private var searchEngine: String

    private static let emojis = ["🌱", "💼", "🏠", "🎨", "🧪", "📚", "🎮", "🎵", "🛒", "✈️", "💡", "🔥", "🌊", "🍕", "🐦", "🧑‍💻",
                                 "📈", "🧠", "❤️", "⭐️", "🌙", "☕️", "🏃", "📷", "🎬", "🧩", "🪴", "🏔️", "🛠️", "💰", "📝", "🎯"]

    /// `initialProfile` is a new space's starting profile (Arc: the focused space's).
    init(existing: Space?, profiles: [BrowserProfile], initialProfile: UUID? = nil,
         searchEngines: [ChromiumSearchEngine] = [], defaultEngineName: String = "Google",
         onSave: @escaping (String, SpaceIcon, SpaceTheme, SpaceProfileChoice, String, String?) -> Void, onCancel: @escaping () -> Void,
         onPreview: @escaping (SpaceTheme) -> Void = { _ in }) {
        self.existing = existing
        self.profiles = profiles
        self.defaultEngineName = defaultEngineName
        // An engine no longer listed (removed on the settings page) still shows as the space's.
        let own = existing?.searchEngine ?? ""
        var engines = searchEngines
        if !own.isEmpty, !engines.contains(where: { $0.keyword.lowercased() == own.lowercased() }) {
            engines.append(ChromiumSearchEngine(name: own, keyword: own, url: ""))
        }
        self.searchEngines = engines
        _searchEngine = State(initialValue: engines.first { $0.keyword.lowercased() == own.lowercased() }?.keyword ?? "")
        _profile = State(initialValue: .existing(existing == nil ? initialProfile : existing?.profileID))
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPreview = onPreview
        _title = State(initialValue: existing?.title ?? "")
        _icon = State(initialValue: existing?.icon ?? .newSpace)
        _theme = State(initialValue: existing?.theme ?? SpaceColorPresets.newSpaceTheme())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(existing == nil ? "New Space" : "Edit Space").font(.system(size: 16, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    HStack(spacing: 6) {
                        iconButton
                        TextField("Name", text: $title).textFieldStyle(.roundedBorder)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Text(e).font(.system(size: 16)).frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(icon == .emoji(e) ? Color.accentColor.opacity(0.25) : .clear))
                                .onTapGesture { icon = .emoji(e) }
                        }
                    }
                    Divider()
                    profileSection
                    searchEngineSection
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
                    onSave(title.isEmpty ? "Space" : title, icon, theme, profile, trimmedProfileName, searchEngine.isEmpty ? nil : searchEngine)
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
                    glyph(size: 15, color: theme.palette.textPrimary)
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

    /// Arc's icon picker (Emoji / Icon / Remove Icon) in a popover, as Change Space Icon… opens
    /// it; the grid below keeps a few emoji one click away.
    private var iconButton: some View {
        Button { pickingIcon = true } label: {
            Group {
                if icon == .none {
                    Image(systemName: "face.dashed").font(.system(size: 14)).foregroundStyle(.secondary)
                } else {
                    glyph(size: 16, color: .primary)
                }
            }
            .frame(width: 28, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(pickingIcon ? 0.14 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change Icon")
        .accessibilityLabel("Change Icon")
        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
            SpaceIconPicker(current: icon.emoji, currentSymbol: icon.symbol, currentImage: icon.image,
                            onPick: { icon = .emoji($0); pickingIcon = false },
                            onPickSymbol: { icon = .symbol($0); pickingIcon = false },
                            onPickImage: { icon = .image($0); pickingIcon = false },
                            onRemove: { icon = .none; pickingIcon = false })
        }
    }

    /// The icon as the sidebar draws it: an emoji, a symbol in the space's text colour, or the user's picture in its own colours.
    @ViewBuilder
    private func glyph(size: CGFloat, color: Color) -> some View {
        switch icon {
        case .emoji(let e): Text(e).font(.system(size: size))
        case .symbol(let name): Image(systemName: name).font(.system(size: size - 2, weight: .medium)).foregroundStyle(color)
        case .image(let data):
            if let image = SpaceIconImage.image(data, points: size + 2) { Image(nsImage: image) }
        case .none: EmptyView()
        }
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

    /// GitHub #306, not in Arc: the engine the command bar searches in this space.
    private var searchEngineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Search Engine", selection: $searchEngine) {
                Text("Default (\(defaultEngineName))").tag("")
                Divider()
                ForEach(searchEngines, id: \.keyword) { e in Text(e.name).tag(e.keyword) }
            }
            Text("Searches from the command bar in this space go here. Default follows Settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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
