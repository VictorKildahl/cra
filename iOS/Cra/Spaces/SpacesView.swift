import CraCore
import SwiftUI

final class SpacesModel: ObservableObject {
    enum State {
        case loading, unavailable, nothingSynced
        case spaces(SidebarDocument)
    }

    @Published var state: State = .loading
    @Published var closedFolders = Set<UUID>()
    @Published var selected: UUID?
    var open: (String) -> Void = { _ in }
    var favicon: (String) -> UIImage? = { _ in nil }
    var close: () -> Void = {}

    var spaces: [MobileSpaces.SpaceView] {
        guard case .spaces(let document) = state else { return [] }
        return MobileSpaces.spaces(in: document, closedFolders: closedFolders)
    }

    func load() {
        SyncedSidebar.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .spaces(let document):
                self.state = .spaces(document)
                if self.selected == nil { self.selected = self.spaces.first?.id }
            case .nothingSynced: self.state = .nothingSynced
            case .unavailable: self.state = .unavailable
            }
        }
    }
}

/// Arc Search's Spaces view: the desktop's Spaces, one a page, each tinted with its colour: the
/// Space's name, its pinned tabs and folders, then Today; the Spaces' icons along the bottom.
struct SpacesView: View {
    @ObservedObject var model: SpacesModel

    var body: some View {
        let spaces = model.spaces
        ZStack {
            tint(for: spaces.first { $0.id == model.selected }).ignoresSafeArea()
            if spaces.isEmpty {
                empty
            } else {
                VStack(spacing: 0) {
                    TabView(selection: $model.selected) {
                        ForEach(spaces) { space in
                            page(space).tag(Optional(space.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if spaces.count > 1 { icons(spaces) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: model.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .padding(.trailing, 24)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("spaces-close")
        }
        // White text on a dark Space, as Arc Search draws it (`MobileSpaces.sheetStyle`).
        .environment(\.colorScheme, style(for: spaces.first { $0.id == model.selected })?.lightText == true ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: model.selected)
        .onAppear { model.load() }
    }

    private func page(_ space: MobileSpaces.SpaceView) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(space.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                    .padding(.top, 22)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("space-title")
                ForEach(space.rows) { row in
                    rowView(row)
                }
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func rowView(_ row: MobileSpaces.Row) -> some View {
        switch row.kind {
        case .todayHeader:
            Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1).padding(.vertical, 12)
        case .folder:
            Button {
                if model.closedFolders.contains(row.id) { model.closedFolders.remove(row.id) } else { model.closedFolders.insert(row.id) }
            } label: {
                label(row, icon: Image(systemName: model.closedFolders.contains(row.id) ? "folder.fill" : "folder").foregroundStyle(.primary.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space-folder-\(row.title)")
        case .tab(let url):
            Button { model.open(url) } label: {
                label(row, icon: FaviconView(image: model.favicon(url)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space-tab-\(row.title)")
        }
    }

    private func label(_ row: MobileSpaces.Row, icon: some View) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 22, height: 22)
            Text(row.title).font(.system(size: 17, weight: .medium)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(height: 56)
        .padding(.leading, CGFloat(row.depth) * 22)
        .contentShape(Rectangle())
    }

    private func icons(_ spaces: [MobileSpaces.SpaceView]) -> some View {
        HStack(spacing: 30) {
            ForEach(spaces) { space in
                Button { model.selected = space.id } label: {
                    Group {
                        if let symbol = space.symbol, UIImage(systemName: symbol) != nil {
                            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                        } else {
                            Text(space.emoji.isEmpty ? "•" : space.emoji).font(.system(size: 19))
                        }
                    }
                    .opacity(space.id == model.selected ? 1 : 0.4)
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("space-icon-\(space.title)")
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var empty: some View {
        if case .loading = model.state {
            ProgressView().accessibilityIdentifier("spaces-loading")
        } else {
            SyncIntroView(iCloud: { if case .unavailable = model.state { return false } else { return true } }())
        }
    }

    /// The Space's colour, softened as Arc Search's sheet is.
    private func tint(for space: MobileSpaces.SpaceView?) -> Color {
        guard let fill = style(for: space)?.fill, let color = UIColor(hex: fill) else { return Color(.systemGroupedBackground) }
        return Color(color)
    }

    private func style(for space: MobileSpaces.SpaceView?) -> MobileSpaces.SheetStyle? {
        space.flatMap { MobileSpaces.sheetStyle(colors: $0.colors) }
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
            Color(red: 0.91, green: 0.94, blue: 0.99).ignoresSafeArea()
            VStack {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.75, green: 0.8, blue: 0.92), Color(red: 0.86, green: 0.89, blue: 0.96)], startPoint: .topLeading, endPoint: .bottom)
                    RadialGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.57).opacity(0.85), .clear], center: .init(x: 0.75, y: 0.15), startRadius: 0, endRadius: 260)
                }
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .ignoresSafeArea()
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
