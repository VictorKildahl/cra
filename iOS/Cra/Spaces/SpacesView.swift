import CraCore
import SwiftUI

final class SpacesModel: ObservableObject {
    enum State {
        case loading, unavailable, nothingSynced
        case spaces(SidebarDocument)
    }

    @Published var state: State = .loading
    /// Folders opened by a tap; Arc Search shows them shut.
    @Published var openFolders = Set<UUID>()
    @Published var selected: UUID?
    /// "Save links to Cra from other apps!" stands in front of the Spaces (asked once).
    @Published var asksToShare = false
    var open: (String) -> Void = { _ in }
    /// Whether the share prompt was answered before, and recording that it now has been.
    var sharePromptSeen: () -> Bool = { true }
    var markSharePromptSeen: () -> Void = {}
    /// Opens the how-to sheet over this one; calls back once it is closed.
    var showShareGuide: (@escaping () -> Void) -> Void = { $0() }
    var favicon: (String) -> UIImage? = { _ in nil }
    /// Asks the site for its icon when the phone has none (its home page names it).
    var fetchFavicon: (String) -> Void = { _ in }
    var close: () -> Void = {}
    private var iconObserver: NSObjectProtocol?

    init() {
        iconObserver = NotificationCenter.default.addObserver(forName: FaviconStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit { iconObserver.map(NotificationCenter.default.removeObserver) }

    var spaces: [MobileSpaces.SpaceView] {
        guard case .spaces(let document) = state else { return [] }
        return MobileSpaces.spaces(in: document, openFolders: openFolders)
    }

    func load() {
        if LaunchOptions.holdsConnecting { return }
        SyncedSidebar.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .spaces(let document):
                self.asksToShare = MobileSyncIntro.showsSharePrompt(hasSpaces: true, seen: self.sharePromptSeen())
                self.state = .spaces(document)
                if self.selected == nil { self.selected = self.spaces.first?.id }
                self.fetchIcons(MobileSpaces.spaces(in: document, openFolders: Set(document.items.map(\.id))))
            case .nothingSynced: self.state = .nothingSynced
            case .unavailable: self.state = .unavailable
            }
        }
    }

    /// "Set up" keeps the prompt behind the how-to sheet (Arc's pushed-back card shows it) until
    /// that is closed; then, or after "No, thanks", the Spaces.
    func answerSharePrompt(setUp: Bool) {
        markSharePromptSeen()
        if setUp {
            showShareGuide { [weak self] in self?.asksToShare = false }
        } else {
            asksToShare = false
        }
    }

    /// Every tab's icon, folders' contents included, so opening a folder shows them at once.
    private func fetchIcons(_ spaces: [MobileSpaces.SpaceView]) {
        for space in spaces {
            for row in space.rows {
                if case .tab(let url) = row.kind, favicon(url) == nil { fetchFavicon(url) }
            }
        }
    }
}

/// Arc Search's Spaces view (Victor's screenshots of 1.49, 13 Nov, iPhone 16 Pro Max): the
/// desktop's Spaces, one a page, each in its colour: the Space's name and a close disc, its pinned
/// tabs and folders (shut until tapped), a line, Today; the Spaces' icons in a bar along the
/// bottom. In dark mode the sheet is a dark shade of the Space's colour
/// (`MobileSpaces.darkSheetStyle`), in light mode a soft tint (`MobileSpaces.sheetStyle`).
struct SpacesView: View {
    @ObservedObject var model: SpacesModel
    @Environment(\.colorScheme) private var scheme

    /// Measured on the 440 pt screen: name and close disc centred 40 pt below the sheet's top,
    /// rows 56 pt apart, 21 pt icons at x 29, text at x 61, a folder's rows 21 pt in.
    private enum Metrics {
        static let side: CGFloat = 29
        static let row: CGFloat = 56
        static let icon: CGFloat = 21
        static let gap: CGFloat = 11
        static let indent: CGFloat = 21
        static let bar: CGFloat = 50
        static let header: CGFloat = 80
        static let rowsTop: CGFloat = 64
    }

    var body: some View {
        let spaces = model.spaces
        let current = spaces.first { $0.id == model.selected }
        let palette = palette(for: current)
        ZStack {
            if spaces.isEmpty || model.asksToShare { palette.background.ignoresSafeArea() }
            if case .loading = model.state {
                ConnectingView().transition(.opacity)
            } else if spaces.isEmpty {
                empty
            } else if model.asksToShare {
                SharePromptView(setUp: { model.answerSharePrompt(setUp: true) }, noThanks: { model.answerSharePrompt(setUp: false) })
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    TabView(selection: $model.selected) {
                        ForEach(spaces) { space in
                            page(space, palette: self.palette(for: space)).tag(Optional(space.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if spaces.count > 1 { icons(spaces, palette: palette) }
                }
                .background(palette.background.ignoresSafeArea())
                // The list's own bottom corners (IMG_1900: 27.3 pt in 0.3 pt up, a continuous 26 pt);
                // "Connecting" and the share prompt run square to the edge.
                .mask(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous).ignoresSafeArea())
            }
        }
        .overlay(alignment: .topTrailing) {
            // Arc Search's "Connecting" and share prompt have no close button.
            if case .loading = model.state {
            } else if model.asksToShare && !spaces.isEmpty {
            } else if !spaces.isEmpty {
                closeButton(palette)
            } else {
                closeButton(palette).environment(\.colorScheme, .light)
            }
        }
        .environment(\.colorScheme, palette.lightText ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: model.selected)
        .animation(.easeInOut(duration: 0.3), value: model.asksToShare)
        .onAppear { model.load() }
    }

    private func closeButton(_ palette: Palette) -> some View {
        Button(action: model.close) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.closeGlyph)
                .frame(width: 24, height: 24)
                .background(palette.closeDisc, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .padding(.trailing, 21)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("spaces-close")
    }

    /// A Space's page: its rows scroll under a fixed header with the name (centred 40 pt down, 80
    /// tall, the first row's top 16 pt under it), which gets a hairline once they do.
    private func page(_ space: MobileSpaces.SpaceView, palette: Palette) -> some View {
        SpacePage(header: Metrics.header, rowsTop: Metrics.rowsTop, edge: palette.text.opacity(0.12), headerFill: palette.headerFill) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(space.rows) { row in
                    rowView(row, palette: palette)
                }
            }
            .padding(.horizontal, Metrics.side)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        } title: {
            Text(space.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.title)
                .lineLimit(1)
                .padding(.leading, Metrics.side)
                .padding(.trailing, 70)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("space-title")
        }
    }

    @ViewBuilder private func rowView(_ row: MobileSpaces.Row, palette: Palette) -> some View {
        switch row.kind {
        case .todayHeader:
            Rectangle().fill(palette.text.opacity(0.14)).frame(height: 1)
                .frame(height: 30)
                .accessibilityHidden(true)
        case .folder(let open):
            Button {
                if open { model.openFolders.remove(row.id) } else { model.openFolders.insert(row.id) }
            } label: {
                label(row, palette: palette, icon: FolderGlyph(open: open, front: palette.folderFront, back: palette.folderBack, edge: palette.folderEdge))
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Open" : "Closed")
            .accessibilityIdentifier("space-folder-\(row.title)")
        case .tab(let url):
            Button { model.open(url) } label: {
                label(row, palette: palette, icon: icon(for: url, palette: palette))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space-tab-\(row.title)")
        }
    }

    /// The site's icon, or Arc Search's plain rounded square while there is none.
    @ViewBuilder private func icon(for url: String, palette: Palette) -> some View {
        if let image = model.favicon(url) {
            if palette.lightText, FaviconStore.isMark(image) {
                Image(uiImage: image.withRenderingMode(.alwaysTemplate)).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(palette.text)
            } else {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.placeholder)
        }
    }

    private func label(_ row: MobileSpaces.Row, palette: Palette, icon: some View) -> some View {
        HStack(spacing: Metrics.gap) {
            icon.frame(width: Metrics.icon, height: Metrics.icon)
            Text(row.title).font(.system(size: 18)).lineLimit(1).foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.row)
        .padding(.leading, CGFloat(row.depth) * Metrics.indent)
        .contentShape(Rectangle())
    }

    /// The bar: the Spaces' icons 63 pt apart, the shown one bright, the rest faded into the bar.
    private func icons(_ spaces: [MobileSpaces.SpaceView], palette: Palette) -> some View {
        HStack(spacing: 29) {
            ForEach(spaces) { space in
                Button { model.selected = space.id } label: {
                    Group {
                        if let symbol = space.symbol, UIImage(systemName: symbol) != nil {
                            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.text)
                        } else {
                            Text(space.emoji.isEmpty ? "•" : space.emoji).font(.system(size: 20))
                        }
                    }
                    .saturation(space.id == model.selected ? 1 : 0.3)
                    .opacity(space.id == model.selected ? 1 : 0.45)
                    .frame(width: 34, height: 34)
                    // Centred 39 pt under the bar's top edge, past the middle of its 50.
                    .offset(y: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(space.title)
                .accessibilityAddTraits(space.id == model.selected ? .isSelected : [])
                .accessibilityIdentifier("space-icon-\(space.title)")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.bar)
        .background {
            palette.bar.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(palette.barEdge).frame(height: 1 / 3) }
        }
    }

    private var empty: some View {
        SyncIntroView(iCloud: { if case .unavailable = model.state { return false } else { return true } }())
    }

    /// The colours of one Space's sheet.
    private struct Palette {
        var background: AnyView
        var bar: Color
        var barEdge: Color
        var title: Color
        var text: Color
        var folderFront: Color
        var folderBack: Color
        var folderEdge: Color
        var headerFill: Color
        var placeholder: Color
        var closeDisc: Color
        var closeGlyph: Color
        var lightText: Bool
    }

    private func palette(for space: MobileSpaces.SpaceView?) -> Palette {
        func color(_ hex: String) -> Color { UIColor(hex: hex).map(Color.init) ?? .clear }
        if scheme == .dark, let dark = space.flatMap({ MobileSpaces.darkSheetStyle(colors: $0.colors) }) {
            return Palette(
                background: AnyView(LinearGradient(colors: [color(dark.top), color(dark.bottom)], startPoint: .top, endPoint: .bottom)),
                bar: color(dark.bar), barEdge: color(dark.title).opacity(0.3),
                title: color(dark.title), text: color(dark.text),
                folderFront: color(dark.folderFront), folderBack: color(dark.folderBack), folderEdge: color(dark.folderEdge),
                headerFill: color(dark.top), placeholder: Color.white.opacity(0.16),
                closeDisc: color(dark.closeDisc), closeGlyph: color(dark.top), lightText: true)
        }
        let style = space.flatMap { MobileSpaces.sheetStyle(colors: $0.colors) }
        let fill = style.flatMap { UIColor(hex: $0.fill) }.map(Color.init) ?? Color(.systemGroupedBackground)
        let light = style?.lightText == true
        let ink: Color = light ? .white : .black
        return Palette(
            background: AnyView(fill), bar: fill.opacity(1), barEdge: ink.opacity(0.08),
            title: ink.opacity(0.9), text: ink.opacity(0.85),
            folderFront: ink.opacity(0.45), folderBack: ink.opacity(0.25), folderEdge: ink.opacity(0.6), headerFill: fill,
            placeholder: ink.opacity(0.12), closeDisc: ink.opacity(0.12), closeGlyph: ink.opacity(0.5), lightText: light)
    }
}

/// A Space's rows under a fixed header that takes a hairline once they scroll under it.
private struct SpacePage<Rows: View, Title: View>: View {
    let header: CGFloat
    let rowsTop: CGFloat
    let edge: Color
    let headerFill: Color
    @ViewBuilder let rows: Rows
    @ViewBuilder let title: Title
    @State private var scrolled = false

    var body: some View {
        ScrollView {
            rows
                .padding(.top, rowsTop)
                .background(alignment: .top) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollTopKey.self, value: proxy.frame(in: .named("space-page")).minY)
                    }
                }
        }
        .coordinateSpace(.named("space-page"))
        .onPreferenceChange(ScrollTopKey.self) { top in
            let now = top < -0.5
            if now != scrolled { scrolled = now }
        }
        .modifier(ScrolledWatch(scrolled: $scrolled))
        .overlay(alignment: .top) {
            title
                .frame(height: header)
                .frame(maxWidth: .infinity)
                // Opaque always: it is the sheet's top colour, so it shows only as rows pass under it.
                .background(headerFill)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(edge).frame(height: 1 / 3).opacity(scrolled ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.15), value: scrolled)
                // The first row runs under the header: taps there are the row's.
                .allowsHitTesting(false)
        }
    }
}

/// On iOS 18 the scroll view says itself whether it has moved; the preference above can miss it.
private struct ScrolledWatch: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in
                if now != scrolled { scrolled = now }
            }
        } else {
            content
        }
    }
}

private struct ScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Arc Search's folder: a light back panel with its tab, a deeper front, both edged in the
/// Space's light tint; open, the front tips forward.
private struct FolderGlyph: View {
    let open: Bool
    let front: Color
    let back: Color
    let edge: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let line: CGFloat = 1.6
            var backPath = Path()
            backPath.move(to: CGPoint(x: 0, y: h * 0.12))
            backPath.addQuadCurve(to: CGPoint(x: w * 0.1, y: 0), control: CGPoint(x: 0, y: 0))
            backPath.addLine(to: CGPoint(x: w * 0.36, y: 0))
            backPath.addLine(to: CGPoint(x: w * 0.47, y: h * 0.16))
            backPath.addLine(to: CGPoint(x: w * 0.9, y: h * 0.16))
            backPath.addQuadCurve(to: CGPoint(x: w, y: h * 0.28), control: CGPoint(x: w, y: h * 0.16))
            backPath.addLine(to: CGPoint(x: w, y: h * 0.88))
            backPath.addQuadCurve(to: CGPoint(x: w * 0.9, y: h), control: CGPoint(x: w, y: h))
            backPath.addLine(to: CGPoint(x: w * 0.1, y: h))
            backPath.addQuadCurve(to: CGPoint(x: 0, y: h * 0.88), control: CGPoint(x: 0, y: h))
            backPath.closeSubpath()
            context.fill(backPath, with: .color(back))
            context.stroke(backPath, with: .color(edge), lineWidth: line)
            let frontPath: Path
            if open {
                var p = Path()
                p.move(to: CGPoint(x: w * 0.2, y: h * 0.42))
                p.addLine(to: CGPoint(x: w * 1.04, y: h * 0.42))
                p.addLine(to: CGPoint(x: w * 0.86, y: h))
                p.addLine(to: CGPoint(x: -w * 0.02, y: h))
                p.closeSubpath()
                frontPath = p
            } else {
                frontPath = Path(roundedRect: CGRect(x: 0, y: h * 0.3, width: w, height: h * 0.7), cornerRadius: w * 0.12, style: .continuous)
            }
            context.fill(frontPath, with: .color(front))
            context.stroke(frontPath, with: .color(edge), lineWidth: line)
        }
        .frame(width: 22, height: 18)
        .accessibilityHidden(true)
    }
}

extension UIColor {
    /// "#RRGGBB" or "RRGGBB".
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    func blended(with other: UIColor, by amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}

/// Before anything has synced: Cra's version of Arc Search's "Sync with Arc Desktop" sheet
/// (`MobileSyncIntro`), pale with a coral and blue glow at the top, the logo, the title in
/// Arc's blue and two buttons; each leads to a page with a drawn smile and "Go back".
struct SyncIntroView: View {
    let iCloud: Bool
    @State private var page: MobileSyncIntro.Page = .intro

    private let blue = Color(red: 0.208, green: 0.31, blue: 1)

    var body: some View {
        ZStack {
            SyncGlow(background: SyncGlow.connectingBackground).ignoresSafeArea(edges: .bottom)
            Group {
                switch page {
                case .intro: intro
                case .haveMac: detail(MobileSyncIntro.haveMacTitle, MobileSyncIntro.haveMacBody(iCloud: iCloud))
                case .noMac: detail(MobileSyncIntro.noMacTitle, MobileSyncIntro.noMacBody)
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: page)
        .environment(\.colorScheme, .light)
        // A container, so the identifier isn't copied onto every text inside.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spaces-empty")
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Spacer()
            Image("LaunchMark").resizable().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(MobileSyncIntro.title).font(.system(size: 30, weight: .heavy)).foregroundStyle(blue).multilineTextAlignment(.center)
                .accessibilityIdentifier("sync-title")
            Text(MobileSyncIntro.body).font(.system(size: 16)).foregroundStyle(Color(white: 0.25)).multilineTextAlignment(.center)
            Spacer()
            button(MobileSyncIntro.haveMacButton, id: "sync-have-mac") { page = .haveMac }
            button(MobileSyncIntro.noMacButton, id: "sync-no-mac") { page = .noMac }
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 22)
    }

    private func detail(_ title: String, _ body: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Smile().stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 64, height: 56).accessibilityHidden(true)
            Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(blue).multilineTextAlignment(.center)
                .accessibilityIdentifier("sync-detail-title")
            Text(body).font(.system(size: 16)).foregroundStyle(Color(white: 0.3)).multilineTextAlignment(.center)
            Spacer()
            Spacer()
            Button { page = .intro } label: {
                Label(MobileSyncIntro.goBack, systemImage: "arrow.left").font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
            }
            .accessibilityIdentifier("sync-go-back")
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 44)
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Arc Search's drawn smile: two short strokes for eyes over a curve.
private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.36, y: 0)); path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.4))
        path.move(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.05)); path.addLine(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.38))
        path.move(to: CGPoint(x: 0, y: rect.height * 0.7))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.85), control: CGPoint(x: rect.width * 0.45, y: rect.height * 1.15))
        return path
    }
}
