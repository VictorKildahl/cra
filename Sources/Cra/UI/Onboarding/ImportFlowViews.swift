import SwiftUI

// Metrics measured from Dia 1.54's import window at 2x (window 928×544 pt, left
// column inset 32, art panel from x 451); colours from its asset catalogs
// (BoostBrowser_UnboxingUI / BoostBrowser_Onboarding), dark values checked
// against pixels. See docs/arc-reverse-engineering.md, "Dia import onboarding".
enum ImportMetrics {
    static let inset: CGFloat = 32
    static let columnWidth: CGFloat = 440
    static let titleTop: CGFloat = 56
    static let subtitleTop: CGFloat = 104
    static let listTop: CGFloat = 174
    static let listHeight: CGFloat = 280
    static let buttonTop: CGFloat = 470
    static let buttonHeight: CGFloat = 42
    static let artX: CGFloat = 451
    static let card = CGSize(width: 215, height: 80)
    static let gap: CGFloat = 10
}

struct ImportColors {
    let dark: Bool
    var background: Color { dark ? .black : .white }
    /// RebrandAppTitleText
    var title: Color { dark ? .white.opacity(0.85) : .black.opacity(0.85) }
    /// RebrandBodyText
    var body: Color { dark ? .white.opacity(0.55) : .black.opacity(0.55) }
    var ink: Color { dark ? .white : .black }
    /// Browser card hairline: #5E5E5E / #9D9D9D over black.
    var cardBorder: Color { dark ? .white.opacity(0.37) : .black.opacity(0.14) }
    var cardBorderSelected: Color { dark ? .white.opacity(0.62) : .black.opacity(0.42) }
    /// BrowserItemBackground (hover)
    var cardHover: Color { dark ? .white.opacity(0.04) : .black.opacity(0.04) }
    /// Radio ring: #505050 over black.
    var radioRing: Color { dark ? .white.opacity(0.31) : .black.opacity(0.22) }
    /// RebrandRowBackground / RebrandRowBorder
    var rowFill: Color { dark ? .white.opacity(0.08) : .black.opacity(0.015) }
    var rowFillHover: Color { dark ? .white.opacity(0.11) : .black.opacity(0.04) }
    var rowBorder: Color { dark ? .white.opacity(0.16) : .black.opacity(0.08) }
    /// ImportSelectionCaption
    var caption: Color { dark ? .white.opacity(0.4) : .black.opacity(0.3) }
    /// ButtonPrimaryBackground: #E0E0E0 over black.
    var primaryFill: Color { dark ? Color(white: 0.878) : .black.opacity(0.85) }
    var primaryFillHover: Color { dark ? Color(white: 0.92) : .black.opacity(0.9) }
    var primaryText: Color { dark ? .black : .white }
    var primaryTextDisabled: Color { dark ? Color(white: 0.5) : .white.opacity(0.5) }
    /// ButtonDefaultBackground
    var secondaryFill: Color { dark ? .white.opacity(0.08) : .black.opacity(0.08) }
    var secondaryFillHover: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    /// ImportProgressItemBorder
    var tileBorder: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    /// LoadingSubtitle
    var loading: Color { dark ? .white.opacity(0.4) : .black.opacity(0.3) }
}

struct ImportFlowView: View {
    @Bindable var model: ImportFlowModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = ImportColors(dark: scheme == .dark)
        ZStack(alignment: .topLeading) {
            c.background
            if model.step == .outro {
                // Dia's RebrandOutroView fills the window: logo, then the welcome line.
                OutroStep(model: model, c: c)
                    .transition(.opacity)
            } else {
                ImportArtPanel(model: model, colors: c)
                    .frame(width: ImportWindowController.size.width - ImportMetrics.artX, height: ImportWindowController.size.height)
                    .offset(x: ImportMetrics.artX)
                    .transition(.opacity)
                Group {
                    switch model.step {
                    case .cover: CoverStep(model: model, c: c)
                    case .defaultBrowser: DefaultBrowserStep(model: model, c: c)
                    case .privacy: PrivacyStep(model: model, c: c)
                    case .source: SourceStep(model: model, c: c)
                    case .safariExport, .passwordsFile: ExportedFileStep(model: model, c: c)
                    case .unlock: UnlockStep(model: model, c: c)
                    case .spaces: SpacesStep(model: model, c: c)
                    case .extensions: ExtensionsStep(model: model, c: c)
                    case .progress: ProgressStep(model: model, c: c)
                    case .credentialsResult: CredentialsResultStep(model: model, c: c)
                    case .pinnedTabs: PinnedTabsStep(model: model, c: c)
                    case .personalization: PersonalizationStep(model: model, c: c)
                    case .outro: EmptyView()
                    }
                }
                .frame(width: ImportMetrics.columnWidth + 2, height: ImportWindowController.size.height, alignment: .topLeading)
                .offset(x: ImportMetrics.inset)
                .id(model.step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: model.forward ? 16 : -16)),
                                        removal: .opacity.combined(with: .offset(x: model.forward ? -16 : 16))))
            }
            if !model.firstRun && (model.step != .progress || model.finished) {
                CloseButton(c: c) { model.onClose() }
                    .offset(x: 887, y: 16)
            }
        }
        .frame(width: ImportWindowController.size.width, height: ImportWindowController.size.height)
        .ignoresSafeArea()
    }
}

// MARK: - Steps

struct StepHeader: View {
    let title: String
    let subtitle: String
    let c: ImportColors
    var body: some View {
        // Dia sets these in Exposure; New York is the closest face macOS ships.
        Text(title)
            .font(.system(size: 29, weight: .regular, design: .serif))
            .tracking(-0.6)
            .foregroundStyle(c.title)
            .lineLimit(1)
            .frame(width: ImportMetrics.columnWidth, height: 36, alignment: .leading)
            .offset(y: ImportMetrics.titleTop)
        Text(subtitle)
            .font(.system(size: 15))
            .lineSpacing(2.5)
            .foregroundStyle(c.body)
            .frame(width: 431, height: 46, alignment: .topLeading)
            .offset(y: ImportMetrics.subtitleTop)
    }
}

/// Dia's NewDefaultBrowserView: three DefaultBrowserCheckboxRows (title and
/// subtitle over the rebrand row background) under a two-line title.
private struct DefaultBrowserStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let system = model.system
        ZStack(alignment: .topLeading) {
            Text("Fast, secure, and packed with all your browser essentials")
                .font(.system(size: 29, weight: .regular, design: .serif))
                .tracking(-0.6)
                .foregroundStyle(c.title)
                .lineLimit(2)
                .lineSpacing(1)
                .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
                .offset(y: ImportMetrics.titleTop)
            VStack(alignment: .leading, spacing: 8) {
                SelectableRow(c: c, checked: system.isDefaultBrowser || model.setAsDefault, disabled: system.isDefaultBrowser,
                              toggle: { model.setAsDefault.toggle() }) {
                    RowTitle(title: "Set Cra as default browser",
                             caption: system.isDefaultBrowser ? "Cra already opens your links" : "Open links and web pages in Cra by default", c: c)
                }
                SelectableRow(c: c, checked: system.isInDock || model.addToDock, disabled: system.isInDock,
                              toggle: { model.addToDock.toggle() }) {
                    RowTitle(title: "Add Cra to Dock",
                             caption: system.isInDock ? "Cra is already in your Dock" : "Quick access to Cra whenever you need it", c: c)
                }
                SelectableRow(c: c, checked: model.launchAtLogin, toggle: { model.launchAtLogin.toggle() }) {
                    RowTitle(title: "Open Cra at login", caption: "Automatically open Cra when you sign in", c: c)
                }
            }
            .frame(width: ImportMetrics.columnWidth)
            .offset(y: ImportMetrics.listTop)
            if let err = model.systemError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
                    .frame(width: ImportMetrics.columnWidth, alignment: .leading)
                    .offset(y: ImportMetrics.buttonTop - 28)
            }
            HStack(spacing: 6) {
                SecondaryButton(title: "Skip", c: c) { model.continueFromDefaultBrowser(applying: false) }
                    .frame(width: 146)
                PrimaryButton(title: system.isPromptingDefault ? "Confirm in the macOS dialog" : "Continue",
                              c: c, enabled: !model.applyingSystemOptions, width: 290) { model.continueFromDefaultBrowser() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct SourceStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Import now to get connected",
                       subtitle: "Import once and stay in your flow. Your spaces, tabs, folders and extensions come with you.", c: c)
            let cols = [GridItem(.fixed(ImportMetrics.card.width), spacing: ImportMetrics.gap),
                        GridItem(.fixed(ImportMetrics.card.width))]
            // Three rows of cards fit; more browsers scroll under a soft edge.
            ScrollView {
                LazyVGrid(columns: cols, alignment: .leading, spacing: ImportMetrics.gap) {
                    ForEach(model.sources) { s in
                        BrowserCard(source: s, model: model, c: c)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 8, alignment: .topLeading)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            if let err = model.loadError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
                    .offset(y: ImportMetrics.buttonTop - 28)
            }
            if model.firstRun {
                // Dia's onboarding offers "skip the importing process" beside Continue.
                HStack(spacing: 6) {
                    SecondaryButton(title: "Skip", c: c) { model.skipImport() }.frame(width: 146)
                    PrimaryButton(title: "Continue", c: c, enabled: model.canContinueFromSource, width: 290) { model.continueFromSource() }
                }
                .frame(width: ImportMetrics.columnWidth + 2)
                .offset(x: -1, y: ImportMetrics.buttonTop)
            } else {
                PrimaryButton(title: "Continue", c: c, enabled: model.canContinueFromSource) { model.continueFromSource() }
                    .offset(x: -1, y: ImportMetrics.buttonTop)
            }
        }
    }
}

private struct SpacesStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let plan = model.plan
        let name = model.source?.rawValue ?? "Arc"
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: "Select spaces to import",
                       subtitle: "We'll import your \(name) spaces, tabs, and folders to Cra.", c: c)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((plan?.spaces ?? []).enumerated()), id: \.offset) { i, sp in
                        SelectableRow(c: c, checked: model.selectedSpaces.contains(i),
                                      onHover: { if $0 { model.previewSpace = i } },
                                      toggle: { model.toggleSpace(i) }) {
                            Text(sp.emoji).font(.system(size: 18)).frame(width: 24)
                            RowTitle(title: sp.title, caption: "\(sp.itemCount) tab\(sp.itemCount == 1 ? "" : "s")", c: c)
                        }
                    }
                    if let plan, !plan.favorites.isEmpty || !plan.archive.isEmpty || model.includeSettings {
                        Text("Also bring over")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(c.caption)
                            .padding(.top, 8).padding(.leading, 2)
                        if !plan.favorites.isEmpty {
                            SelectableRow(c: c, checked: model.includeFavorites, toggle: { model.includeFavorites.toggle() }) {
                                RowSymbol(name: "star.fill", c: c)
                                RowTitle(title: "Favorites", caption: "\(plan.favorites.count) in your current space", c: c)
                            }
                        }
                        if !plan.archive.isEmpty {
                            SelectableRow(c: c, checked: model.includeArchive, toggle: { model.includeArchive.toggle() }) {
                                RowSymbol(name: "archivebox.fill", c: c)
                                RowTitle(title: "Archived Tabs", caption: "\(plan.archive.count) tabs", c: c)
                            }
                        }
                        if !plan.settings.isEmpty {
                            SelectableRow(c: c, checked: model.includeSettings, toggle: { model.includeSettings.toggle() }) {
                                RowSymbol(name: "gearshape.fill", c: c)
                                RowTitle(title: "Settings", caption: plan.settings.linkRoutes.isEmpty ? "Auto-archive, sidebar width and toolbar" : "Auto-archive, toolbar and Air Traffic Control", c: c)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: "Continue", c: c, enabled: model.hasAnythingSelected) { model.continueFromSpaces() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct ExtensionsStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.spaces) }
            StepHeader(title: "Import your extensions",
                       subtitle: "Pick your essentials. You can always add more extensions later as you settle in with Cra.", c: c)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.extensions) { e in
                        let installed = ExtensionStore.isInstalled(id: e.id)
                        // Arc keeps extensions per profile: say which profiles it goes to (#131).
                        let profiles = model.profileNames(of: e).map { " · " + $0.joined(separator: ", ") } ?? ""
                        SelectableRow(c: c, checked: model.selectedExtensions.contains(e.id), toggle: { model.toggleExtension(e.id) }) {
                            ExtensionIcon(image: e.icon, size: 24, c: c)
                            RowTitle(title: e.name,
                                     caption: installed ? "Already in Cra · \(e.version)"
                                        : (e.isEnabled ? e.version + profiles : "Turned off in \(model.source?.rawValue ?? "Arc")"),
                                     c: c)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            HStack(spacing: 6) {
                SecondaryButton(title: "Skip", c: c) { model.startImport(withExtensions: false) }
                    .frame(width: 146)
                PrimaryButton(title: model.selectedExtensions.isEmpty ? "Continue" : "Import \(model.selectedExtensions.count) Extension\(model.selectedExtensions.count == 1 ? "" : "s")",
                              c: c, enabled: true, width: 290) { model.startImport(withExtensions: true) }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct ProgressStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\(model.finished ? "Imported" : "Importing") from \(model.source?.rawValue ?? "Arc")")
                .font(.system(size: 29, weight: .regular, design: .serif))
                .tracking(-0.6)
                .foregroundStyle(c.title)
                .frame(width: ImportMetrics.columnWidth, height: 36, alignment: .leading)
                .offset(y: ImportMetrics.titleTop)
            HStack(spacing: 8) {
                if !model.finished { ProgressView().controlSize(.small) }
                Text(model.finished ? (model.failures.isEmpty ? "Everything is in place." : "Some import steps failed:") : "Hold on while we fetch your data")
                    .font(.system(size: 15)).foregroundStyle(model.finished ? c.body : c.loading)
            }
            .frame(height: 22)
            .offset(y: ImportMetrics.subtitleTop)
            // Up to eight tiles: a fourth row only fits above the notes and the button when the
            // tiles are shorter.
            let compact = model.categories.count > 6
            let gap: CGFloat = compact ? 8 : ImportMetrics.gap
            let cols = [GridItem(.fixed(ImportMetrics.card.width), spacing: ImportMetrics.gap),
                        GridItem(.fixed(ImportMetrics.card.width))]
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: cols, alignment: .leading, spacing: gap) {
                    ForEach(model.categories) { CategoryTile(category: $0, c: c, height: compact ? 52 : 64) }
                }
                // The notes follow the grid, so they never run into the tiles.
                if model.finished {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.failures, id: \.self) { Text($0).lineLimit(2) }
                        if model.importedExtensionCount > 0 {
                            Text("Cra restarts once to load your extensions. Their settings and sign-ins stay in \(model.source?.rawValue ?? "Arc").")
                        } else if model.credentialsStaged {
                            Text("Cra restarts once to bring in your passwords and sign-ins.")
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(c.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: model.needsRelaunch && !model.firstRun && !model.credentialsAttempted ? "Restart Cra" : "Continue",
                          c: c, enabled: model.finished) { model.continueFromProgress() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Controls

/// Soft top and bottom edges on the scrolling lists.
struct ScrollFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
        }
    }
}

/// Dia's ImportBrowserItemView: logo, name, radio; the selected card shows how
/// many spaces will come over, which opens the space picker.
private struct BrowserCard: View {
    let source: ImportSource
    let model: ImportFlowModel
    let c: ImportColors
    @State private var hover = false

    var body: some View {
        let selected = model.source == source
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(hover ? c.cardHover : .clear)
            shape.strokeBorder(selected ? c.cardBorderSelected : c.cardBorder, lineWidth: 0.5)
            Image(nsImage: source.icon)
                .resizable().interpolation(.high)
                .frame(width: 52, height: 52)
                .offset(x: 19, y: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.rawValue).font(.system(size: 16, weight: .medium)).foregroundStyle(c.title)
                if selected, let plan = model.plan, !plan.spaces.isEmpty {
                    Button { model.continueFromSource() } label: {
                        Text("\(model.selectedSpaces.count) of \(plan.spaces.count) spaces")
                            .font(.system(size: 11)).foregroundStyle(c.body).underline(hover)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(width: 80, height: ImportMetrics.card.height, alignment: .leading)
            .offset(x: 82)
            RadioDot(on: selected, c: c)
                .offset(x: 161.5, y: 28)
        }
        .frame(width: ImportMetrics.card.width, height: ImportMetrics.card.height)
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { model.select(source) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { withAnimation(.easeOut(duration: 0.18)) { model.select(source) } }
    }
}

/// 24 pt ring (1.5 pt); selected adds a 17.5 pt disc.
struct RadioDot: View {
    let on: Bool
    let c: ImportColors
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? c.ink.opacity(0.98) : c.radioRing, lineWidth: 1.5)
            if on { Circle().fill(c.ink.opacity(0.98)).frame(width: 17.5, height: 17.5).transition(.scale.combined(with: .opacity)) }
        }
        .frame(width: 24, height: 24)
    }
}

/// Dia's rebrand_checkbox: 18 pt rounded square, filled with a tick when on.
struct CheckBox: View {
    let on: Bool
    let c: ImportColors
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            if on {
                shape.fill(c.ink.opacity(0.9))
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(c.background)
            } else {
                shape.strokeBorder(c.ink.opacity(0.3), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// Dia's ImportSelectableCheckBox / SpaceCheckboxView row.
struct SelectableRow<Content: View>: View {
    let c: ImportColors
    let checked: Bool
    /// Already true on this Mac: shown ticked, not changeable.
    var disabled = false
    var onHover: (Bool) -> Void = { _ in }
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 12) {
            content()
            Spacer(minLength: 8)
            CheckBox(on: checked, c: c).opacity(disabled ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(shape.fill(hover && !disabled ? c.rowFillHover : c.rowFill))
        .overlay(shape.strokeBorder(c.rowBorder, lineWidth: 0.5))
        .contentShape(shape)
        .onHover { hover = $0; onHover($0) }
        .onTapGesture { if !disabled { withAnimation(.easeOut(duration: 0.15)) { toggle() } } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if !disabled { withAnimation(.easeOut(duration: 0.15)) { toggle() } } }
    }
}

struct RowTitle: View {
    let title: String
    let caption: String
    let c: ImportColors
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(c.title).lineLimit(1)
            Text(caption).font(.system(size: 12)).foregroundStyle(c.caption).lineLimit(1)
        }
    }
}

struct RowSymbol: View {
    let name: String
    let c: ImportColors
    var body: some View {
        Image(systemName: name).font(.system(size: 14)).foregroundStyle(c.body).frame(width: 24)
    }
}

struct ExtensionIcon: View {
    let image: NSImage?
    let size: CGFloat
    let c: ImportColors
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Image(systemName: "puzzlepiece.extension.fill").font(.system(size: size * 0.6)).foregroundStyle(c.body).frame(width: size, height: size)
        }
    }
}

struct CategoryTile: View {
    let category: ImportCategory
    let c: ImportColors
    var height: CGFloat = 64
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: category.symbol).font(.system(size: 15)).foregroundStyle(c.body).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.title).font(.system(size: 14, weight: .medium)).foregroundStyle(c.title)
                Text(category.detail).font(.system(size: 12)).foregroundStyle(c.caption).lineLimit(1)
            }
            Spacer(minLength: 4)
            Group {
                switch category.state {
                case .waiting: Circle().strokeBorder(c.radioRing, lineWidth: 1.5).frame(width: 18, height: 18)
                case .working: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(c.ink.opacity(0.9))
                case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundStyle(.orange)
                }
            }
            .frame(width: 22, height: 22)
            .transition(.scale.combined(with: .opacity))
        }
        .padding(.horizontal, 14)
        .frame(width: ImportMetrics.card.width, height: height)
        .overlay(shape.strokeBorder(c.tileBorder, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: category.state)
    }
}

/// Full-width primary button with Dia's return-key glyph.
struct PrimaryButton: View {
    let title: String
    let c: ImportColors
    let enabled: Bool
    var width: CGFloat = ImportMetrics.columnWidth + 2
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button { if enabled { action() } } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Image(systemName: "return").font(.system(size: 12, weight: .medium)).opacity(0.75)
            }
            .foregroundStyle(enabled ? c.primaryText : c.primaryTextDisabled)
            .frame(maxWidth: .infinity)
            .frame(height: ImportMetrics.buttonHeight)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hover && enabled ? c.primaryFillHover : c.primaryFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
        .frame(width: width)
    }
}

struct SecondaryButton: View {
    let title: String
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.body)
                .frame(maxWidth: .infinity)
                .frame(height: ImportMetrics.buttonHeight)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hover ? c.secondaryFillHover : c.secondaryFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }
}

struct BackLink: View {
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Back").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hover ? c.title : c.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .offset(y: 22)
    }
}

private struct CloseButton: View {
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .light))
                .foregroundStyle(c.dark ? .white.opacity(hover ? 0.95 : 0.7) : .black.opacity(hover ? 0.8 : 0.5))
                .shadow(color: .black.opacity(c.dark ? 0.3 : 0), radius: 2)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hover = $0 }
        .accessibilityLabel("Close")
    }
}
