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

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "desktopcomputer").font(.system(size: 34, weight: .medium)).foregroundStyle(.secondary)
            switch model.state {
            case .loading:
                ProgressView()
            case .unavailable:
                Text("Spaces come from Cra on your Mac").font(.system(size: 17, weight: .semibold))
                Text("Sign in to iCloud on this iPhone, and turn on Sync in Cra on your Mac under Settings ▸ General.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            default:
                Text("Nothing synced yet").font(.system(size: 17, weight: .semibold))
                Text("Turn on Sync in Cra on your Mac under Settings ▸ General, and keep iCloud Drive on for Cra on this iPhone (Settings ▸ your name ▸ iCloud ▸ iCloud Drive). Your Spaces show up here.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .accessibilityIdentifier("spaces-empty")
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
