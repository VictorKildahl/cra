import SwiftUI

// The parts Settings pictures are drawn from. A setting that changes how Cra looks carries a
// picture the way Arc's Max pane does (an 88×56 drawing on a pastel, in a white frame): a few
// parts of a browser window put together to show the change. Pictures keep their colours in dark mode,
// as Arc's do.

/// A picture's colours: the tile, the window's sidebar (a space colour) and the ink for the
/// part the setting is about.
struct ArtTint {
    let bg: Color
    let theme: Color
    let ink: Color

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let lavender = ArtTint(bg: rgb(0.86, 0.84, 0.97), theme: rgb(0.68, 0.64, 0.92), ink: rgb(0.40, 0.33, 0.82))
    static let mint = ArtTint(bg: rgb(0.81, 0.93, 0.87), theme: rgb(0.48, 0.77, 0.63), ink: rgb(0.12, 0.52, 0.36))
    static let peach = ArtTint(bg: rgb(0.99, 0.88, 0.80), theme: rgb(0.95, 0.66, 0.50), ink: rgb(0.84, 0.38, 0.16))
    static let sky = ArtTint(bg: rgb(0.81, 0.89, 0.98), theme: rgb(0.50, 0.68, 0.94), ink: rgb(0.15, 0.40, 0.84))
    static let rose = ArtTint(bg: rgb(0.98, 0.85, 0.89), theme: rgb(0.92, 0.57, 0.67), ink: rgb(0.80, 0.22, 0.40))
    static let lemon = ArtTint(bg: rgb(0.99, 0.94, 0.76), theme: rgb(0.94, 0.80, 0.36), ink: rgb(0.70, 0.50, 0.04))
    static let slate = ArtTint(bg: rgb(0.88, 0.89, 0.92), theme: rgb(0.62, 0.65, 0.71), ink: rgb(0.28, 0.31, 0.39))
    static let mauve = ArtTint(bg: rgb(0.89, 0.83, 0.90), theme: rgb(0.66, 0.53, 0.68), ink: rgb(0.45, 0.27, 0.52))

    /// Page text and other neutral marks.
    static let line = Color(white: 0.84)
    static let faint = Color(white: 0.92)
}

/// The 88×56 tile a picture is drawn on; parts sit at points from its top left with `.at`.
struct ArtCanvas<Content: View>: View {
    let tint: ArtTint
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            tint.bg
            content
        }
        .frame(width: 88, height: 56, alignment: .topLeading)
    }
}

extension View {
    /// Places a part `x`, `y` points into its ArtCanvas (or any top-left-aligned stack).
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { offset(x: x, y: y) }
    /// The soft shadow under windows, cards and keys.
    func artLift(_ radius: CGFloat = 1.5) -> some View { shadow(color: .black.opacity(0.18), radius: radius, y: 0.6) }
}

/// The traffic lights, 2.2 pt across.
struct ArtLights: View {
    var body: some View {
        HStack(spacing: 1.2) {
            ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 2.2, height: 2.2) }
        }
    }
}

/// Lines of page text: grey capsules of mixed lengths.
struct ArtLines: View {
    var count = 4
    var width: CGFloat = 30
    var height: CGFloat = 2
    var spacing: CGFloat = 2.5
    var color = ArtTint.line
    private static let lengths: [CGFloat] = [1, 0.75, 0.9, 0.55, 0.85, 0.65]
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(color).frame(width: width * Self.lengths[i % Self.lengths.count], height: height)
            }
        }
    }
}

/// A browser window: the sidebar in the space colour with tab rows, the page as a white card
/// inset 2 pt (or filling the window edge to edge), an optional toolbar across the page.
struct ArtWindow<Page: View>: View {
    var tint: ArtTint
    var width: CGFloat = 70
    var height: CGFloat = 46
    var sidebar = true
    var rows = 4
    var selected: Int? = 1
    var toolbar = false
    var edgeToEdge = false
    @ViewBuilder var page: Page

    private let sidebarWidth: CGFloat = 18

    var body: some View {
        let x: CGFloat = sidebar ? sidebarWidth : (edgeToEdge ? 0 : 2)
        let inset: CGFloat = edgeToEdge ? 0 : 2
        ZStack(alignment: .topLeading) {
            tint.theme
            ArtLights().at(3, 3.5)
            if sidebar {
                ForEach(0..<rows, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(i == selected ? 0.95 : 0.45))
                        .frame(width: sidebarWidth - 5, height: 3.2)
                        .at(2.5, 10 + CGFloat(i) * 5.2)
                }
            }
            ZStack(alignment: .topLeading) {
                Color.white
                VStack(alignment: .leading, spacing: 0) {
                    if toolbar {
                        Capsule().fill(ArtTint.faint).frame(width: 20, height: 3).padding(.leading, 3).frame(height: 6)
                        Rectangle().fill(ArtTint.faint).frame(height: 0.6)
                    }
                    page
                }
            }
            .frame(width: width - x - inset, height: height - 2 * inset, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: edgeToEdge ? 0 : 2.5, style: .continuous))
            .at(x, inset)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .artLift()
    }
}

extension ArtWindow where Page == AnyView {
    /// A window whose page is a few lines of text.
    init(tint: ArtTint, width: CGFloat = 70, height: CGFloat = 46, sidebar: Bool = true, rows: Int = 4,
         selected: Int? = 1, toolbar: Bool = false, edgeToEdge: Bool = false) {
        self.init(tint: tint, width: width, height: height, sidebar: sidebar, rows: rows, selected: selected,
                  toolbar: toolbar, edgeToEdge: edgeToEdge) {
            AnyView(ArtLines(count: 4, width: (width - 30) * 0.8).padding(.leading, 4).padding(.top, 5))
        }
    }
}

/// One sidebar row drawn large: favicon, title, white when it is the open tab.
struct ArtTabRow: View {
    var favicon: Color = ArtTint.line
    var width: CGFloat = 46
    var title: CGFloat = 0.6
    var selected = false
    var symbol: String?
    var ink: Color = .black

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 5, weight: .bold)).foregroundStyle(ink).frame(width: 5, height: 5)
            } else {
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(favicon).frame(width: 5, height: 5)
            }
            Capsule().fill(Color.black.opacity(selected ? 0.35 : 0.22)).frame(width: (width - 14) * title, height: 2.2)
        }
        .padding(.horizontal, 3)
        .frame(width: width, height: 9, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(selected ? Color.white : Color.white.opacity(0.001)))
        .artLiftIf(selected)
    }
}

/// A piece of sidebar drawn large: the space colour behind rows stacked on a 10 pt pitch.
struct ArtSidebar<Content: View>: View {
    var tint: ArtTint
    var width: CGFloat = 52
    var height: CGFloat = 50
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 1) { content }
            .padding(3)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.theme))
            .artLift()
    }
}

/// A white card floating over the picture: a Peek, a popover, the command bar, a menu.
struct ArtCard<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat = 3
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            content
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)
    }
}

/// An SF Symbol mark in a picture.
struct ArtSymbol: View {
    let name: String
    var size: CGFloat = 12
    var color: Color = .black
    var weight: Font.Weight = .semibold
    var body: some View {
        Image(systemName: name).font(.system(size: size, weight: weight)).foregroundStyle(color)
    }
}

/// The pointer, black with a white rim.
struct ArtCursor: View {
    var size: CGFloat = 10
    var body: some View {
        ZStack {
            Image(systemName: "cursorarrow").font(.system(size: size + 1.4, weight: .black)).foregroundStyle(.white)
            Image(systemName: "cursorarrow").font(.system(size: size, weight: .regular)).foregroundStyle(.black)
        }
        .shadow(color: .black.opacity(0.25), radius: 0.8, y: 0.4)
    }
}

/// A favorite's tile with a logo in it.
struct ArtFavorite: View {
    var logo: Color
    var symbol: String?
    var width: CGFloat = 16
    var height: CGFloat = 12
    var selected = false
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.white.opacity(selected ? 1 : 0.55))
            .frame(width: width, height: height)
            .overlay {
                if let symbol {
                    ArtSymbol(name: symbol, size: 5.5, color: logo, weight: .bold)
                } else {
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(logo).frame(width: 5, height: 5)
                }
            }
    }
}

extension View {
    @ViewBuilder func artLiftIf(_ on: Bool) -> some View {
        if on { artLift(1) } else { self }
    }
}
