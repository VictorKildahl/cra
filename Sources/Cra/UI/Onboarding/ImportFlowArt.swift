import SwiftUI

// The right-hand panel of the import window. Dia paints these as artwork
// (Rebrand*Screenshot in BoostBrowser_Unboxing) with a live sidebar preview
// (DiaSidebarPreviewView) on the space step; Cra draws its own from the data
// being imported: the badge ring follows Dia's composition, the window mock
// shows the hovered space in its own theme.

struct ImportArtPanel: View {
    let model: ImportFlowModel
    let colors: ImportColors

    var body: some View {
        // Dia paints the default browser step warm (RebrandDefaultBrowserScreenshot).
        let theme = model.step == .defaultBrowser
            ? SpaceTheme(colors: colors.dark ? ["#8A5038", "#5C2A1C"] : ["#E2A585", "#F1D9C8"], intensity: 1, noise: 0.2, appearance: colors.dark ? "dark" : "light")
            : model.previewTheme ?? SpaceTheme(colors: colors.dark ? ["#2A3440", "#151A20"] : ["#DCE6F0", "#C4D3E2"],
                                               intensity: 1, noise: 0.2, appearance: colors.dark ? "dark" : "light")
        ZStack(alignment: .topLeading) {
            ArtBackdrop(theme: theme, dark: colors.dark)
            switch model.step {
            case .defaultBrowser:
                DockArt(model: model, colors: colors)
            case .source:
                BadgeRing(model: model, colors: colors, accent: accent(model.previewTheme))
            case .spaces:
                WindowMock(theme: theme, colors: colors) {
                    SidebarPreview(model: model, theme: theme)
                        .id(model.previewSpace)
                        .transition(.opacity)
                } pane: { EmptyView() }
                .animation(.easeInOut(duration: 0.25), value: model.previewSpace)
            case .extensions:
                WindowMock(theme: theme, colors: colors, origin: CGPoint(x: 96, y: 80), sidebarWidth: 120) {
                    PlaceholderSidebar(theme: theme)
                } pane: {
                    ExtensionsPreview(model: model, colors: ImportColors(dark: theme.palette.isDark))
                }
            case .progress:
                BadgeRing(model: model, colors: colors, accent: accent(model.previewTheme))
            case .cover, .privacy:
                // Cover and privacy show only the painted backdrop.
                EmptyView()
            case .personalization:
                // A live preview of a Cra window in the picked theme colour and layout.
                WindowMock(theme: theme, colors: colors, origin: CGPoint(x: 38, y: 76), sidebarWidth: 106,
                           fittedSize: CGSize(width: 423, height: 392)) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.classicLayout {
                            AddressPreview(theme: theme, inSidebar: true)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        PlaceholderSidebar(theme: theme)
                    }
                } pane: {
                    VStack(spacing: 0) {
                        if model.classicLayout {
                            AddressPreview(theme: theme, inSidebar: false)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        SignupPagePreview(draft: model.signupEmailDraft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: theme)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.classicLayout)
            case .unlock, .safariExport, .passwordsFile, .credentialsResult:
                KeyArt(colors: colors, accent: accent(model.previewTheme))
            case .pinnedTabs:
                WindowMock(theme: theme, colors: colors) {
                    PlaceholderSidebar(theme: theme)
                } pane: { EmptyView() }
            case .outro:
                EmptyView()
            }
        }
        .frame(width: 477, height: 544, alignment: .topLeading)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.6), location: model.step == .personalization ? 0.04 : 0.14),
                                     .init(color: .black, location: model.step == .personalization ? 0.08 : 0.3)], startPoint: .leading, endPoint: .trailing))
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: theme)
    }

    /// Dia's badge glyphs are a pale blue (#A7D3E8); a space's accent replaces it.
    private func accent(_ t: SpaceTheme?) -> Color {
        let base = Color(hex: t.map { $0.accent ?? $0.colors.first ?? "#8EC5E3" } ?? "#8EC5E3")
        return colors.dark ? base.blendedToward(.white, 0.25) : base.blendedToward(.white, 0.35)
    }
}

/// Soft blurred colour fields with grain, standing in for Dia's paintings.
private struct ArtBackdrop: View {
    let theme: SpaceTheme
    let dark: Bool
    var body: some View {
        let c0 = Color(hex: theme.colors.first ?? "#C4D3E2")
        let c1 = Color(hex: theme.colors.count > 1 ? theme.colors[1] : (theme.colors.first ?? "#DCE6F0"))
        let base: Color = dark ? Color(white: 0.06) : Color(white: 0.93)
        ZStack {
            base
            Ellipse().fill(c0.opacity(dark ? 0.55 : 0.75)).frame(width: 340, height: 460).blur(radius: 70).offset(x: 130, y: -120)
            Ellipse().fill(c1.opacity(dark ? 0.5 : 0.7)).frame(width: 300, height: 360).blur(radius: 80).offset(x: 170, y: 190)
            Ellipse().fill((dark ? Color.white : Color.white).opacity(dark ? 0.06 : 0.55)).frame(width: 220, height: 300).blur(radius: 60).offset(x: -20, y: 40)
            Image(nsImage: NoiseTexture.image).resizable(resizingMode: .tile)
                .opacity(dark ? 0.08 : 0.07).blendMode(dark ? .screen : .multiply)
        }
        .frame(width: 477, height: 544)
    }
}

// MARK: - Dock

/// After Dia's RebrandDefaultBrowserScreenshot (476×544 pt): the app's tile
/// lifted out of a glass Dock between two neighbours, a running dot under it.
/// The left neighbour is the current default browser, where Cra's tile lands.
private struct DockArt: View {
    let model: ImportFlowModel
    let colors: ImportColors

    var body: some View {
        let system = model.system
        let docked = system.isInDock || model.addToDock
        let glass = Color.white.opacity(colors.dark ? 0.16 : 0.32)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(glass)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(colors.dark ? 0.18 : 0.45), lineWidth: 1))
                .frame(width: 420, height: 167)
                .offset(x: 88, y: 205)
            NeighbourTile(icon: system.defaultBrowserURL.map { NSWorkspace.shared.icon(forFile: $0.path) }, dark: colors.dark)
                .offset(x: 64, y: 235)
            // Right neighbour: Arc (Dia when Arc is already the default on the left).
            NeighbourTile(icon: neighbourIcon(excluding: system.defaultBrowserURL), dark: colors.dark)
                .offset(x: 368, y: 235)
            // A macOS icon's artwork fills 824 of its 1024 pt canvas; Dia's tile is 144 pt.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 144 * 1024 / 824, height: 144 * 1024 / 824)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                .scaleEffect(docked ? 1 : 0.86)
                .opacity(docked ? 1 : 0.45)
                .position(x: 269, y: docked ? 199.5 : 228)
            Circle().fill(Color(white: 0.12))
                .frame(width: 10, height: 10)
                .position(x: 269, y: 338)
                .opacity(docked ? 1 : 0)
        }
        .frame(width: 477, height: 544, alignment: .topLeading)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: docked)
    }

    private func neighbourIcon(excluding defaultBrowser: URL?) -> NSImage? {
        for source in [ImportSource.arc, .dia] {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID),
                  url.standardizedFileURL != defaultBrowser?.standardizedFileURL else { continue }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

private struct NeighbourTile: View {
    let icon: NSImage?
    let dark: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 106 * 1024 / 824, height: 106 * 1024 / 824)
                    .opacity(0.85)
            } else {
                shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.22 : 0.6), .white.opacity(dark ? 0.1 : 0.3)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(.white.opacity(dark ? 0.25 : 0.7), lineWidth: 1)
            }
        }
        .frame(width: 106, height: 106)
    }
}

/// The unlock and passwords steps: a key over the same two rings as the badge ring.
private struct KeyArt: View {
    let colors: ImportColors
    let accent: Color
    var body: some View {
        ZStack {
            ForEach([118.0, 140.0], id: \.self) { r in
                Circle().strokeBorder(colors.ink.opacity(colors.dark ? 0.14 : 0.18), lineWidth: 1)
                    .frame(width: r * 2 * (477 / 448), height: r * 2 * (477 / 448))
            }
            Circle().fill(colors.dark ? Color(white: 0.13) : Color(white: 0.97))
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(colors.dark ? 0.4 : 0.14), radius: 16, y: 6)
            Image(systemName: "key.fill").font(.system(size: 58, weight: .regular)).foregroundStyle(accent)
        }
        .frame(width: 477, height: 544)
    }
}

// MARK: - Badge ring

/// Positions follow Dia's RebrandImportScreenshot (448×544 pt) scaled to the
/// 477 pt panel: five badges around the app mark inside two rings.
private struct BadgeRing: View {
    let model: ImportFlowModel
    let colors: ImportColors
    let accent: Color

    private static let scale: CGFloat = 477 / 448
    private static let badges: [(id: String, symbol: String, x: CGFloat, y: CGFloat, r: CGFloat)] = [
        ("tabs", "pin.fill", 155, 145, 29),
        ("spaces", "square.stack.fill", 376, 120, 44),
        ("favorites", "star.fill", 392, 277, 21),
        ("extensions", "puzzlepiece.extension.fill", 122, 362, 23),
        ("archive", "archivebox.fill", 288, 434, 34),
    ]

    var body: some View {
        let s = Self.scale
        ZStack(alignment: .topLeading) {
            ForEach([118.0, 140.0], id: \.self) { r in
                Circle().strokeBorder(colors.ink.opacity(colors.dark ? 0.14 : 0.18), lineWidth: 1)
                    .frame(width: r * 2 * s, height: r * 2 * s)
                    .position(x: 263 * s, y: 272)
            }
            BrandMark(size: 132)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                .position(x: 263 * s, y: 272)
            ForEach(Self.badges, id: \.id) { b in
                Badge(symbol: b.symbol, radius: b.r * s, state: state(b.id), colors: colors, accent: accent)
                    .position(x: b.x * s, y: b.y)
            }
        }
        .frame(width: 477, height: 544, alignment: .topLeading)
    }

    private func state(_ id: String) -> ImportCategory.State? {
        guard model.step == .progress else { return nil }
        // Pinned tabs and folders share a tile with spaces' contents.
        return model.categories.first { $0.id == id }?.state ?? .waiting
    }
}

private struct Badge: View {
    let symbol: String
    let radius: CGFloat
    let state: ImportCategory.State?
    let colors: ImportColors
    let accent: Color

    var body: some View {
        let lit = state == nil || state == .done || state == .working
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(colors.dark ? Color(white: 0.13).opacity(0.92) : Color(white: 0.95))
                Circle().strokeBorder(colors.dark ? Color.white.opacity(0.12) : .white, lineWidth: colors.dark ? 1 : 2.5)
                Image(systemName: symbol).font(.system(size: radius * 0.78, weight: .medium)).foregroundStyle(accent)
            }
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: .black.opacity(colors.dark ? 0.4 : 0.12), radius: 8, y: 3)
            if state == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: max(14, radius * 0.5)))
                    .foregroundStyle(colors.dark ? .white : .black, colors.dark ? Color(white: 0.13) : .white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(lit ? 1 : 0.4)
        .scaleEffect(state == .working ? 1.08 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state)
    }
}

// MARK: - Window mock

/// After Dia's RebrandArcImportPreviewScreenshot: a window entering from the
/// lower right, traffic lights at its top left, sidebar beside a content pane.
private struct WindowMock<Sidebar: View, Pane: View>: View {
    let theme: SpaceTheme
    let colors: ImportColors
    /// Dia's window enters at (124, 80) of its 448 pt artwork, sidebar 243 pt wide.
    var origin = CGPoint(x: 132, y: 80)
    var sidebarWidth: CGFloat = 236
    /// A complete window for Personalization; the import artwork crops its window at the far edge.
    var fittedSize: CGSize?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let pane: () -> Pane

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let palette = theme.palette
        ZStack(alignment: .topLeading) {
            SpaceBackground(palette: palette)
                .background(palette.isDark ? Color(white: 0.1) : Color(white: 0.96))
            sidebar()
                .frame(width: sidebarWidth, alignment: .topLeading)
                .padding(.top, 48)
            HStack(spacing: 9) {
                ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 13, height: 13) }
            }
            .offset(x: 19, y: 20)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.isDark ? Color(white: 0.12) : .white)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .overlay(alignment: .topLeading) { pane() }
                .frame(width: fittedSize.map { $0.width - sidebarWidth - 12 } ?? 400,
                       height: fittedSize.map { $0.height - 20 } ?? 500)
                .offset(x: sidebarWidth + 6, y: 10)
        }
        .frame(width: fittedSize?.width ?? 520, height: fittedSize?.height ?? 520, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(colors.dark ? 0.12 : 0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(colors.dark ? 0.5 : 0.18), radius: 24, y: 10)
        .offset(x: origin.x, y: origin.y)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }
}

/// Dia's DiaSidebarPreviewView: favourites grid, space name, pinned tabs and
/// folders of the space being looked at.
private struct SidebarPreview: View {
    let model: ImportFlowModel
    let theme: SpaceTheme

    var body: some View {
        let p = theme.palette
        if let plan = model.plan, let i = model.previewSpace, i < plan.spaces.count {
            let space = plan.spaces[i]
            let favorites = Array((space.favorites + (model.includeFavorites ? plan.favorites : [])).filter { !$0.isFolder }.prefix(8))
            VStack(alignment: .leading, spacing: 10) {
                if !favorites.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                        ForEach(Array(favorites.enumerated()), id: \.offset) { _, f in
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.pillFill)
                                .frame(height: 40)
                                .overlay(Favicon(image: model.favicon(for: f), size: 17, palette: p))
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text(space.emoji).font(.system(size: 12))
                    Text(space.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.textSecondary)
                }
                .padding(.leading, 4)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(space.pinned.prefix(9).enumerated()), id: \.offset) { _, item in
                        PreviewRow(item: item, model: model, palette: p)
                    }
                    if !space.today.isEmpty {
                        Rectangle().fill(p.separator).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 6)
                        ForEach(Array(space.today.prefix(4).enumerated()), id: \.offset) { _, item in
                            PreviewRow(item: item, model: model, palette: p)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .opacity(model.selectedSpaces.contains(i) ? 1 : 0.35)
        }
    }
}

private struct PreviewRow: View {
    let item: ImportedItem
    let model: ImportFlowModel
    let palette: SpacePalette
    var body: some View {
        HStack(spacing: 9) {
            if item.isFolder {
                Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(palette.folderTint).frame(width: 16)
            } else {
                Favicon(image: model.favicon(for: item), size: 16, palette: palette)
            }
            Text(item.customTitle ?? (item.pageTitle.isEmpty ? (item.url ?? "") : item.pageTitle))
                .font(.system(size: 13)).foregroundStyle(palette.textPrimary).lineLimit(1)
            if item.isFolder {
                Text("\(item.children.count)").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}

private struct Favicon: View {
    let image: NSImage?
    let size: CGFloat
    let palette: SpacePalette
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundStyle(palette.textTertiary).frame(width: size, height: size)
        }
    }
}

private struct PlaceholderSidebar: View {
    let theme: SpaceTheme
    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 12) {
            ForEach([0.7, 0.5, 0.82, 0.6, 0.44], id: \.self) { w in
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 4).fill(p.textTertiary.opacity(0.5)).frame(width: 16, height: 16)
                    Capsule().fill(p.textTertiary.opacity(0.35)).frame(width: 70 * w, height: 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// A sample website inside the live theme/layout illustration. It has no editable web form;
/// the editable profile address lives in the left column.
private struct SignupPagePreview: View {
    let draft: String

    var body: some View {
        let address = SignupEmail.address(draft)
        let showOffer = address != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Text("Create an account")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 19)
            Text("Email address")
                .font(.system(size: 12, weight: .medium))
                .padding(.bottom, 5)
            HStack {
                Text("Enter your email").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5))
            .padding(.bottom, 4)
            SignupEmailPreview(address: address ?? "you@example.com")
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(showOffer ? 1 : 0)
                .accessibilityHidden(!showOffer)
        }
        .padding(.horizontal, 14)
    }
}

/// The address bar of the personalization preview: Arc's second sidebar row
/// (nav buttons and a URL pill), or the toolbar strip above the page.
private struct AddressPreview: View {
    let theme: SpaceTheme
    let inSidebar: Bool
    var body: some View {
        let p = theme.palette
        if inSidebar {
            // Arc's toolbar-hidden URL pill: the sidebar's width less 8 pt a side, the bare host.
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.pillFill)
                .frame(height: 34)
                .overlay(alignment: .leading) {
                    Text("example.com").font(.system(size: 12.5)).foregroundStyle(p.textPrimary).padding(.leading, 11)
                }
                .padding(.horizontal, 8)
        } else {
            let ink: Color = p.isDark ? .white : .black
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sidebar.left").font(.system(size: 11)).foregroundStyle(ink.opacity(0.45))
                    navButtons(p, ink: ink)
                    Text("example.com").font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                Rectangle().fill(ink.opacity(0.08)).frame(height: 1)
            }
        }
    }

    private func navButtons(_ p: SpacePalette, ink: Color? = nil) -> some View {
        HStack(spacing: 7) {
            ForEach(["arrow.left", "arrow.right", "arrow.clockwise"], id: \.self) {
                Image(systemName: $0).font(.system(size: 10, weight: .medium)).foregroundStyle(ink.map { $0.opacity(0.45) } ?? p.textTertiary)
            }
        }
    }
}

/// The content pane on the extensions step: a toolbar pill of the picked
/// extensions (Dia's screenshot puts its Chat pill there) and their icons.
private struct ExtensionsPreview: View {
    let model: ImportFlowModel
    let colors: ImportColors
    var body: some View {
        let picked = model.extensions.filter { model.selectedExtensions.contains($0.id) }
        let fill = colors.dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ForEach(picked.prefix(5)) { ExtensionIcon(image: $0.icon, size: 16, c: colors) }
                Image(systemName: "puzzlepiece.extension").font(.system(size: 13)).foregroundStyle(colors.body)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
            .animation(.easeOut(duration: 0.2), value: model.selectedExtensions)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 12), count: 3), alignment: .leading, spacing: 12) {
                ForEach(picked.prefix(9)) { e in
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
                        .frame(width: 58, height: 58)
                        .overlay(ExtensionIcon(image: e.icon, size: 30, c: colors))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.selectedExtensions)
        }
        .padding(.top, 14)
        .padding(.leading, 16)
    }
}
