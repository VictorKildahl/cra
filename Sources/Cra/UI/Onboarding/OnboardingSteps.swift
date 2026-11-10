import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The onboarding steps Dia 1.54 shows around the import: a cover page, the
// privacy (ad blocker) screen, the "Unlock your data" password step and its
// result, Safari's exported-file drop, pinned tabs, personalization and the
// outro. See docs/arc-reverse-engineering.md, "Dia onboarding steps".

/// Two lines of Dia's serif title; the import steps use StepHeader (one line).
struct TwoLineHeader: View {
    let title: String
    let subtitle: String
    let c: ImportColors
    var body: some View {
        Text(title)
            .font(.system(size: 29, weight: .regular, design: .serif))
            .tracking(-0.6)
            .foregroundStyle(c.title)
            .lineLimit(2)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.titleTop - 14)
        Text(subtitle)
            .font(.system(size: 15))
            .lineSpacing(2.5)
            .foregroundStyle(c.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 431, alignment: .topLeading)
            .offset(y: ImportMetrics.subtitleTop + 10)
    }
}

// MARK: - Cover

/// Dia's auth cover page: wordmark, a one-line pitch, Get Started and Sign In.
struct CoverStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 18) {
                BrandMark(size: 56)
                Text("A calmer way\nto browse")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .tracking(-0.8)
                    .foregroundStyle(c.title)
                    .lineSpacing(2)
                Text("Cra is a native macOS browser with a sidebar instead of a tab strip. Spaces, pinned tabs, a command bar that learns, and an archive that tidies up after you.")
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(c.body)
                    .frame(width: 400, alignment: .leading)
            }
            .offset(y: 150)
            // Dia pairs this with a Sign In button; Cra has no accounts for now.
            PrimaryButton(title: "Get Started", c: c, enabled: true) { model.continueFromCover() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Privacy (Dia's DisclosureView, ad blocker half)

struct PrivacyStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            TwoLineHeader(title: "Privacy in Cra,\nyou're in control",
                          subtitle: "Cra works fully signed out. Your spaces, tabs and archive are plain files on your Mac.", c: c)
            SelectableRow(c: c, checked: model.blockAdsAndTrackers, toggle: { model.blockAdsAndTrackers.toggle() }) {
                RowSymbol(name: "hand.raised.fill", c: c)
                RowTitle(title: "Block third-party ads and trackers",
                         caption: "You won't see them. And they won't see you.", c: c)
            }
            .frame(width: ImportMetrics.columnWidth)
            .offset(y: ImportMetrics.listTop)
            PrimaryButton(title: "Continue", c: c, enabled: true) { model.continueFromPrivacy() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Unlock passwords and cookies (Dia's ImportProfilePickerView)

struct UnlockStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let many = model.credentialProfiles.count > 1
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: "Unlock your data for import",
                       subtitle: model.unlockReadsSidebar
                           ? "Dia encrypts your spaces, tabs and passwords, so macOS will ask for your computer password."
                           : many ? "Some data is encrypted, so macOS will ask for your computer password once for each selected profile."
                                  : "Some data is encrypted, so macOS will ask for your computer password to bring it securely into Cra.", c: c)
            if many {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.credentialProfiles) { p in
                            SelectableRow(c: c, checked: model.selectedProfiles.contains(p.id), toggle: { model.toggleProfile(p.id) }) {
                                RowSymbol(name: "person.crop.circle", c: c)
                                RowTitle(title: p.name, caption: "Passwords and sign-ins", c: c)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
                .mask(ScrollFade())
                .offset(y: ImportMetrics.listTop - 8)
            } else {
                HStack(spacing: 12) {
                    RowSymbol(name: "key.fill", c: c)
                    RowTitle(title: "Passwords and sign-ins",
                             caption: "So you don't have to enter all your passwords again", c: c)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(width: ImportMetrics.columnWidth, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.rowFill))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.rowBorder, lineWidth: 0.5))
                .offset(y: ImportMetrics.listTop)
            }
            if let err = model.unlockError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red.opacity(0.85))
                    .frame(width: ImportMetrics.columnWidth, alignment: .leading)
                    .offset(y: ImportMetrics.buttonTop - 44)
            }
            HStack(spacing: 6) {
                SecondaryButton(title: "Skip", c: c) { model.skipCredentials() }.frame(width: 146)
                PrimaryButton(title: model.unlocking ? "Waiting for password" : model.unlockError == nil ? "Continue" : "Try Again",
                              c: c, enabled: !model.unlocking, width: 290) { model.unlock() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Exported file (Dia's SafariExportedDataView; also Firefox and Zen passwords)

struct ExportedFileStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    @State private var dropTargeted = false

    private var isSafari: Bool { model.source?.kind == .safari }
    private var browser: String { model.source?.name ?? "Firefox" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: isSafari ? "Import from Safari" : "Import \(browser) passwords",
                       subtitle: isSafari ? "Open Safari and follow these steps to import your passwords, history, and bookmarks."
                                          : "In \(browser), open Settings ▸ Passwords ▸ ⋯ ▸ Export Passwords, then drop the file here.", c: c)
            VStack(alignment: .leading, spacing: 10) {
                if isSafari {
                    InstructionRow(n: 1, text: "Open the Safari app.", c: c)
                    InstructionRow(n: 2, text: "Open File ▸ Export Browsing Data to File.", c: c)
                    InstructionRow(n: 3, text: "Save the file, then drop it below.", c: c)
                }
                DropWell(fileName: model.exportFileName, targeted: dropTargeted, reading: model.readingExport, isSafari: isSafari, c: c) {
                    chooseFile()
                } clear: {
                    model.clearExport()
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.readExport(url) } }
                    }
                    return true
                }
                if let err = model.exportError {
                    Text(err).font(.system(size: 12)).foregroundStyle(.red.opacity(0.85))
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.listTop - (isSafari ? 24 : 0))
            HStack(spacing: 6) {
                SecondaryButton(title: "Skip", c: c) { model.skipExport() }.frame(width: 146)
                PrimaryButton(title: "Continue", c: c, enabled: model.exportFileName != nil, width: 290) { model.continueFromExport() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = isSafari
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = isSafari ? [.zip, .folder] : [.commaSeparatedText]
        panel.prompt = isSafari ? "Choose .zip file" : "Choose .csv file"
        if panel.runModal() == .OK, let url = panel.url { model.readExport(url) }
    }
}

private struct InstructionRow: View {
    let n: Int
    let text: String
    let c: ImportColors
    var body: some View {
        HStack(spacing: 12) {
            Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.title)
                .frame(width: 24, height: 24)
                .background(Circle().fill(c.secondaryFill))
            Text(text).font(.system(size: 14)).foregroundStyle(c.body)
            Spacer()
        }
    }
}

private struct DropWell: View {
    let fileName: String?
    let targeted: Bool
    let reading: Bool
    let isSafari: Bool
    let c: ImportColors
    let choose: () -> Void
    let clear: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: { if fileName == nil { choose() } }) {
            HStack(spacing: 12) {
                if reading {
                    ProgressView().controlSize(.small)
                    Text("Reading…").font(.system(size: 14)).foregroundStyle(c.body)
                } else if let fileName {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(c.ink.opacity(0.9))
                    Text(fileName).font(.system(size: 14, weight: .medium)).foregroundStyle(c.title).lineLimit(1)
                    Spacer()
                    Button(action: clear) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(c.caption) }
                        .buttonStyle(.plain)
                } else {
                    Image(systemName: "arrow.down.doc").font(.system(size: 16)).foregroundStyle(c.body)
                    Text(isSafari ? "Choose .zip file or drag it here" : "Choose .csv file or drag it here")
                        .font(.system(size: 14)).foregroundStyle(c.body)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(targeted ? c.rowFillHover : c.rowFill))
            .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: fileName == nil ? [5, 4] : []))
                .foregroundStyle(targeted ? c.ink.opacity(0.5) : c.rowBorder))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Passwords result (Dia's ImportPasswordsAndCookiesResultView)

struct CredentialsResultStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let ok = model.credentialsSucceeded
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44)).foregroundStyle(ok ? c.ink.opacity(0.9) : .orange)
                Text(ok ? "You're all set" : "Something went wrong")
                    .font(.system(size: 29, weight: .regular, design: .serif)).tracking(-0.6).foregroundStyle(c.title)
                Text(ok ? "Your passwords and cookies are now available in Cra. Start browsing and you'll be signed in to your sites."
                        : "Cra was unable to import your passwords and cookies. You can try again now or skip this step.")
                    .font(.system(size: 15)).lineSpacing(2.5).foregroundStyle(c.body)
                    .frame(width: 420, alignment: .leading)
            }
            .offset(y: 150)
            if ok {
                PrimaryButton(title: "Continue", c: c, enabled: true) { model.afterImport() }
                    .offset(x: -1, y: ImportMetrics.buttonTop)
            } else {
                HStack(spacing: 6) {
                    SecondaryButton(title: "Skip", c: c) { model.afterImport() }.frame(width: 146)
                    PrimaryButton(title: "Try Again", c: c, enabled: true, width: 290) { model.retryCredentials() }
                }
                .frame(width: ImportMetrics.columnWidth + 2)
                .offset(x: -1, y: ImportMetrics.buttonTop)
            }
        }
    }
}

// MARK: - Pinned tabs (Dia's PinnedTabsView)

struct PinnedTabsStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Keep your favorites handy",
                       subtitle: "Pin the apps you use most so they're always a click away in Cra.", c: c)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(model.pinCandidates) { p in
                        PinCard(candidate: p, icon: model.pinIcons[p.host], on: model.selectedPins.contains(p.host), c: c) {
                            model.togglePin(p.host)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 8)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: model.selectedPins.isEmpty ? "Skip" : "Pin \(model.selectedPins.count)", c: c, enabled: true) {
                model.continueFromPinnedTabs()
            }
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
        .onAppear { model.loadPinCandidates() }
    }
}

private struct PinCard: View {
    let candidate: PinCandidate
    let icon: NSImage?
    let on: Bool
    let c: ImportColors
    let toggle: () -> Void
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 7) {
            ZStack {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 26, height: 26)
                } else {
                    Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(c.body)
                }
            }
            .frame(height: 28)
            Text(candidate.name).font(.system(size: 11, weight: .medium)).foregroundStyle(c.title).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 76)
        .background(shape.fill(on ? c.rowFillHover : (hover ? c.rowFillHover.opacity(0.6) : c.rowFill)))
        .overlay(shape.strokeBorder(on ? c.cardBorderSelected : c.rowBorder, lineWidth: on ? 1.5 : 0.5))
        .overlay(alignment: .topTrailing) {
            if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(c.ink.opacity(0.9)).padding(5) }
        }
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { toggle() } }
    }
}

// MARK: - Personalization (Dia's PersonalizationView)

/// Dia 1.54's PersonalizationView: the colour swatches in one row, then "Choose how you would like
/// to view your tabs:" over two PersonalizationTabLayoutButtons (window illustrations, Dia's
/// TabLayout/* artwork, with a ring around the picked one and its name underneath). Dia picks a
/// tab layout; Cra's two layouts place the address bar (Arc's View ▸ Show Toolbar).
struct PersonalizationStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Make it yours",
                       subtitle: "Pick the theme color and layout that feel right for you.", c: c)
            HStack(spacing: (ImportMetrics.columnWidth - 34 * CGFloat(SpaceTheme.presets.count)) / CGFloat(SpaceTheme.presets.count - 1)) {
                ForEach(SpaceTheme.presets.indices, id: \.self) { i in
                    ThemeSwatch(theme: SpaceTheme.presets[i], on: model.chosenTheme == i, c: c) { model.chooseTheme(i) }
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .leading)
            .offset(y: ImportMetrics.listTop)
            Text("Choose where the address bar goes:")
                .font(.system(size: 13))
                .foregroundStyle(c.body)
                .offset(y: 228)
            HStack(spacing: 12) {
                // Settings ▸ Tabs ▸ Address Bar offers the same two (#305).
                ForEach(AddressBarPlacement.allCases, id: \.self) { LayoutTile(placement: $0, model: model, c: c) }
            }
            .offset(y: 252)
            PrimaryButton(title: "Continue", c: c, enabled: true) { model.continueFromPersonalization() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

/// Dia's PersonalizationTabLayoutButton: the illustration at its 230×180 artwork size scaled to
/// the column, a 3 pt ring when picked, the name in TabLayoutLabelText underneath.
private struct LayoutTile: View {
    let placement: AddressBarPlacement
    @Bindable var model: ImportFlowModel
    let c: ImportColors

    private static let width: CGFloat = (ImportMetrics.columnWidth - 12) / 2

    var body: some View {
        let toolbar = placement == .toolbar
        let selected = model.classicLayout == toolbar
        let k = Self.width / 230
        VStack(spacing: 7) {
            LayoutArt(toolbar: toolbar, selected: selected, dark: c.dark)
                .frame(width: 230, height: 180)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: 230 * k, height: 180 * k, alignment: .topLeading)
            // TabLayoutLabelText: black 53% / white 60%.
            Text(placement.title)
                .font(.system(size: 13))
                .foregroundStyle(c.dark ? Color.white.opacity(0.6) : Color.black.opacity(0.53))
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { model.classicLayout = toolbar } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(placement.title): the address bar \(placement.detail.lowercased())")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.classicLayout = toolbar }
    }
}

/// Drawn after Dia's TabLayout/SidebarSelected and friends (230×180 pt): a 3 pt ring, a 2 pt gap,
/// the window inset 5 pt (radius 10), 5 pt traffic lights, 54×14 pt sidebar rows on a 19 pt pitch
/// and the page pane from x 70. Cra's version marks where the address bar sits: the first sidebar
/// row, or a strip across the top of the page.
private struct LayoutArt: View {
    let toolbar: Bool
    let selected: Bool
    let dark: Bool
    var body: some View {
        let window: Color = dark ? Color(white: 0.2) : Color.black.opacity(0.05)
        let row: Color = dark ? Color(white: 0.36) : Color.black.opacity(0.19)
        let pane: Color = dark ? Color(white: 0.12) : .white
        let accent: Color = dark ? Color(white: 0.62) : Color.black.opacity(0.42)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(dark ? Color(white: 0.8) : Color.black.opacity(0.8), lineWidth: 3)
                .opacity(selected ? 1 : 0)
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(window)
                .frame(width: 220, height: 170)
                .offset(x: 5, y: 5)
            ForEach(Array(["#FF5F57", "#FEBC2E", "#28C840"].enumerated()), id: \.offset) { i, hex in
                Circle().fill(Color(hex: hex)).frame(width: 5, height: 5)
                    .offset(x: 13 + CGFloat(i) * 8.5, y: 14)
            }
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(i == 0 && !toolbar ? accent : row)
                    .frame(width: 54, height: 14)
                    .offset(x: 10, y: 27 + CGFloat(i) * 19)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane)
                .frame(width: 150, height: 160)
                .overlay(alignment: .top) {
                    if toolbar {
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(accent)
                                .frame(width: 70, height: 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(height: 18)
                            Rectangle().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)).frame(height: 1)
                        }
                    }
                }
                .offset(x: 70, y: 10)
        }
        .frame(width: 230, height: 180, alignment: .topLeading)
    }
}

private struct ThemeSwatch: View {
    let theme: SpaceTheme
    let on: Bool
    let c: ImportColors
    let tap: () -> Void
    var body: some View {
        let colors = theme.colors.map { Color(hex: $0) }
        Circle()
            .fill(LinearGradient(colors: colors.count > 1 ? colors : [colors.first ?? .gray, colors.first ?? .gray],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(c.ink.opacity(on ? 0.95 : 0), lineWidth: 2).padding(-3))
            .overlay(on ? Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).shadow(radius: 1) : nil)
            .contentShape(Circle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { tap() } }
    }
}


// MARK: - Outro (Dia's RebrandOutroView)

struct OutroStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    @State private var shown = false
    var body: some View {
        VStack(spacing: 22) {
            BrandMark(size: 76)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            Text("Welcome to your new\nhome on the internet")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(c.title)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)
            PrimaryButton(title: "Start browsing", c: c, enabled: true, width: 260) { model.finish() }
                .opacity(shown ? 1 : 0)
                .padding(.top, 8)
        }
        .frame(width: ImportWindowController.size.width, height: ImportWindowController.size.height)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) { shown = true } }
    }
}
