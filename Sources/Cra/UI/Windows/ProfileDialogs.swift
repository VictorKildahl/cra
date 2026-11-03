import SwiftUI

/// Arc 1.171's "Which Spaces should use this Profile?" (the second step of Create a new Profile),
/// measured from a 2x capture (3 Nov): a 450 × 506 pt card; each space as a 63 × 95 pt card in its
/// theme over a 16 pt circle (green with a tick when chosen) and its name, 76 pt apart.
struct ProfileSpacesStep: View {
    let spaces: [Space]
    @Binding var ticked: Set<UUID>
    let onBack: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileAvatar().padding(.top, 38.5)
            Text("Which Spaces should use this Profile?")
                .font(.system(size: 17.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 19)
            Text("These Spaces will start fresh in your brand new Profile — so you’ll have to log back in to websites, re-save your passwords, add extensions, etc. You can always switch back to your previous Profile though if you forgot something!")
                .font(.system(size: 14))
                .lineSpacing(0.7)
                .foregroundStyle(NewProfileDialog.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 375.5, alignment: .leading)
                .padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 13) {
                    ForEach(spaces) { s in
                        SpaceChoice(space: s, on: ticked.contains(s.id)) {
                            if ticked.contains(s.id) { ticked.remove(s.id) } else { ticked.insert(s.id) }
                        }
                    }
                }
                .padding(.horizontal, 38.5)
            }
            .padding(.horizontal, -38.5)
            .frame(height: 155)
            .padding(.top, 14)
            HStack(spacing: 7) {
                Spacer()
                DialogButton(title: "Back", key: "ESC", enabled: true, primary: false, action: onBack)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Create Profile", key: "↩", enabled: true, style: .accent, action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 31)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 38.5)
        .frame(width: 450, height: 506)
        .background(NewProfileDialog.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// One space in the step above: the theme as a little window, the circle, the name.
private struct SpaceChoice: View {
    let space: Space
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 14.5) {
                ZStack {
                    Color(white: space.theme.palette.isDark ? 0.12 : 0.97)
                    SpaceBackground(palette: space.theme.palette)
                }
                .frame(width: 63, height: 95)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                ZStack {
                    if on {
                        Circle().fill(Color(hex: "#007C00"))
                        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Color(hex: "#062A1E"))
                    } else {
                        Circle().strokeBorder(Color(hex: "#5B616F"), lineWidth: 1.5)
                    }
                }
                .frame(width: 16, height: 16)
                Text(space.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#C8CAD2"))
                    .lineLimit(1)
                    .frame(width: 76)
            }
            .frame(width: 63)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space.title)
        .accessibilityValue(on ? "1" : "0")
    }
}

/// Arc 1.171's Spaces ▸ Change Profile (3 Nov): "Change <space>’s Profile" on a 450 × 338 pt
/// card, the space's icon on a blue tile with a profile badge, and a blue pill that picks Default,
/// another profile or New Profile. Change Profile with New Profile goes on to Create a new Profile.
struct ChangeProfileDialog: View {
    let space: Space
    let profiles: [BrowserProfile]
    let others: [Space]
    let onChange: (UUID?) -> Void
    let onCreate: (String, Set<UUID>) -> Void
    let onCancel: () -> Void
    @State private var choice: SpaceProfileChoice
    @State private var creating = false
    @State private var pill = CGRect.zero

    init(space: Space, profiles: [BrowserProfile], spaces: [Space], onChange: @escaping (UUID?) -> Void,
         onCreate: @escaping (String, Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.space = space
        self.profiles = profiles
        self.others = spaces
        self.onChange = onChange
        self.onCreate = onCreate
        self.onCancel = onCancel
        _choice = State(initialValue: .existing(space.profileID))
    }

    var body: some View {
        if creating {
            NewProfileDialog(spaces: others, ticked: [space.id], onCreate: onCreate, onCancel: onCancel)
        } else {
            picker
        }
    }

    private var choiceName: String {
        switch choice {
        case .new: return "New Profile"
        case .existing(let id): return profiles.first { $0.id == id }?.name ?? "Default"
        }
    }

    private func showMenu() {
        // The dialog's own window, which needn't be key (Cra may be in the background).
        guard let content = NSApp.windows.last(where: { $0 is DialogOverlayWindow && $0.isVisible })?.contentView else { return }
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Default") { choice = .existing(nil) }
        for p in profiles { MenuItems.add(m, p.name) { choice = .existing(p.id) } }
        m.addItem(.separator())
        MenuItems.add(m, "New Profile") { choice = .new }
        // SwiftUI's global frame is top-left based in the window; the content view is not flipped.
        let y = content.isFlipped ? pill.maxY + 4 : content.bounds.height - pill.maxY - 4
        // Next turn of the run loop, so the button's press returns before the menu tracks.
        DispatchQueue.main.async { m.popUp(positioning: nil, at: NSPoint(x: pill.minX, y: y), in: content) }
    }

    private func confirm() {
        switch choice {
        case .new: creating = true
        case .existing(let id): if id == space.profileID { onCancel() } else { onChange(id) }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceProfileIcon(space: space).padding(.top, 38)
            (Text("Change ") + Text("\(space.title)’s").bold() + Text(" Profile"))
                .font(.system(size: 17.5))
                .foregroundStyle(.white)
                .padding(.top, 17)
            Text("Each Profile has different browser data, so you might get logged out of some websites, see different Favorites up top, or need to re-install extensions.")
                .font(.system(size: 14))
                .lineSpacing(0.7)
                .foregroundStyle(NewProfileDialog.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 375.5, alignment: .leading)
                .padding(.top, 12)
            HStack(spacing: 6) {
                (Text("\(space.title)’s").bold() + Text(" Profile"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#DBDCDF"))
                // An NSMenu under the pill, like Arc's (Default, the other profiles, New Profile).
                Button(action: showMenu) {
                    // Arc's lavender circle with the chevron cut in the pill's blue, 14 pt.
                    HStack(spacing: 5) {
                        ZStack {
                            Circle().fill(Color(hex: "#BEC0F3"))
                            Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color(hex: "#2E36E7"))
                                .offset(y: 0.5)
                        }
                        .frame(width: 14, height: 14)
                        Text(choiceName).font(.system(size: 14)).foregroundStyle(Color(hex: "#BEC0F3"))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .background(Color(hex: "#2E36E7"), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .background(GeometryReader { g in Color.clear.onAppear { pill = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in pill = f } })
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(choiceName)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showMenu() }
            }
            .padding(.top, 8)
            HStack(spacing: 7) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, primary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Change Profile", key: "↩", enabled: true, style: .accent, action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 27.5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 38.5)
        .frame(width: 450, height: 338)
        .background(NewProfileDialog.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The space's emoji (or Icon-tab glyph) on Arc's 62 pt blue tile, with the profile smiley badge.
private struct SpaceProfileIcon: View {
    let space: Space

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#4049DC"))
                if let symbol = space.symbol {
                    Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.white)
                } else {
                    Text(space.emoji.isEmpty ? "🌱" : space.emoji).font(.system(size: 30))
                }
            }
            .frame(width: 62, height: 62)
            .frame(width: 68, height: 68, alignment: .topLeading)
            ZStack {
                Circle().fill(Color(hex: "#30305D"))
                Circle().strokeBorder(Color(hex: "#6262A3"), lineWidth: 1.5)
                VStack(spacing: 2.5) {
                    HStack(spacing: 3.5) {
                        Capsule().fill(Color(hex: "#C4C4DC")).frame(width: 2, height: 5)
                        Capsule().fill(Color(hex: "#C4C4DC")).frame(width: 2, height: 5)
                    }
                    SmileArc().stroke(Color(hex: "#C4C4DC"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 10, height: 2.5)
                }
            }
            .frame(width: 23, height: 23)
            .overlay(Circle().strokeBorder(NewProfileDialog.card, lineWidth: 2))
        }
        .frame(width: 68, height: 68)
    }
}
