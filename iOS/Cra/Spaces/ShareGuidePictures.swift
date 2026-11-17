import SwiftUI

/// The how-to sheet's pictures. Arc Search shows shrunken screenshots of iOS 17's share sheet; Cra
/// draws the same screens with its own name. Each is laid out in the screenshot's own 411 × 606
/// units (Victor's IMG_1899, 3 px a point, measured from each picture's top left) and drawn at a
/// third of that: 137 × 202 pt.
private enum Picture {
    static let units = CGSize(width: 411, height: 606)
    static let scale: CGFloat = 1.0 / 3
    static let size = CGSize(width: units.width * scale, height: units.height * scale)
    static let sheet = Color(red: 0xE9 / 255, green: 0xE9 / 255, blue: 0xEA / 255)
    static let groupedBackground = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
    static let label = Color.black
    static let secondary = Color(white: 0.55)
    static let blue = Color(red: 0x2F / 255, green: 0x39 / 255, blue: 0xFF / 255)
    static let systemBlue = Color(red: 0x34 / 255, green: 0x78 / 255, blue: 0xF6 / 255)
    static let green = Color(red: 0x65 / 255, green: 0xC4 / 255, blue: 0x66 / 255)
    static let red = Color(red: 0xEB / 255, green: 0x4D / 255, blue: 0x3D / 255)

    /// A picture's frame: drawn in units, shrunk, clipped to rounded corners on a soft shadow.
    static func frame(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack(alignment: .topLeading) { content() }
            .frame(width: units.width, height: units.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    /// Arc's fat blue arrow, white-edged: a shaft from `from` to `to` and an open chevron head.
    static func arrow(from: CGPoint, to: CGPoint) -> some View {
        let shape = ArrowShape(from: from, to: to)
        return ZStack {
            shape.stroke(.white, style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
            shape.stroke(blue, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        }
        .frame(width: units.width, height: units.height)
    }
}

private struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = 34
        for turn in [CGFloat.pi * 0.75, -CGFloat.pi * 0.75] {
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x + head * cos(angle + turn), y: to.y + head * sin(angle + turn)))
        }
        return path
    }
}

/// An app icon in the share sheet: a 62-unit rounded square.
private struct AppIcon<Content: View>: View {
    var fill: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
            .overlay(content)
            .frame(width: 62, height: 62)
    }
}

/// Step 2: a page's share sheet, scrolled to "More", the arrow running along the apps.
struct ShareSheetPicture: View {
    static let size = Picture.size

    var body: some View {
        Picture.frame {
            Color(white: 0.07)
            // The sheet over the page.
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Picture.sheet)
                .frame(width: 411, height: 606 - 183)
                .offset(y: 183)
            // Header: the page's picture, title, address and Options; the close disc.
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.18, green: 0.36, blue: 1))
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<3, id: \.self) { line in
                            Capsule().fill(.white.opacity(0.85)).frame(width: line == 2 ? 26 : 44, height: 3)
                        }
                    }
                    .padding(.leading, 5)
                }
                .frame(width: 64, height: 65)
                .offset(x: 16, y: 199)
            Text("Cra").font(.system(size: 16, weight: .semibold)).foregroundStyle(Picture.label)
                .offset(x: 96, y: 201)
            Text("crabrowser.app").font(.system(size: 14)).foregroundStyle(Picture.secondary)
                .offset(x: 96, y: 222)
            HStack(spacing: 4) {
                Text("Options").font(.system(size: 16))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Picture.secondary)
            }
            .foregroundStyle(Picture.label)
            .frame(width: 96, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.95)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: 0.82), lineWidth: 1))
            .offset(x: 96, y: 248)
            Circle().fill(Color(white: 0.84)).frame(width: 30, height: 30)
                .overlay(Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(white: 0.45)))
                .offset(x: 365, y: 198)
            Rectangle().fill(Color(white: 0.8)).frame(width: 411, height: 1).offset(y: 302)
            // The apps, scrolled past Messages to More.
            apps
            Picture.arrow(from: CGPoint(x: 62, y: 360), to: CGPoint(x: 300, y: 360))
            // Actions.
            row("Copy", symbol: "doc.on.doc", top: 444, corners: (true, true))
            row("Add to Reading List", symbol: "eyeglasses", top: 509, corners: (true, false))
            Rectangle().fill(Color(white: 0.85)).frame(width: 377 - 21, height: 1).offset(x: 37, y: 563)
            row("Add Bookmark", symbol: "book", top: 564, corners: (false, false))
        }
    }

    private var apps: some View {
        ZStack(alignment: .topLeading) {
            AppIcon(fill: Color(red: 0.2, green: 0.8, blue: 0.35)) {
                Image(systemName: "message.fill").font(.system(size: 30)).foregroundStyle(.white)
            }
            .offset(x: -48, y: 326)
            label("es", centre: -2)
            AppIcon {
                Text("N").font(.system(size: 40, weight: .black)).foregroundStyle(Color(red: 0.96, green: 0.27, blue: 0.33))
            }
            .offset(x: 46, y: 326)
            label("News", centre: 77)
            AppIcon {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach([Color.blue, .red, .orange], id: \.self) { color in
                        HStack(spacing: 5) {
                            Circle().strokeBorder(color, lineWidth: 2).frame(width: 9, height: 9)
                            Capsule().fill(Color(white: 0.85)).frame(width: 26, height: 2)
                        }
                    }
                }
            }
            .offset(x: 140, y: 326)
            label("Reminders", centre: 171)
            AppIcon(fill: Color(red: 1, green: 0.84, blue: 0.2)) {
                VStack(spacing: 0) {
                    Color(red: 1, green: 0.84, blue: 0.2).frame(height: 16)
                    Color.white.overlay(alignment: .top) {
                        VStack(spacing: 7) {
                            ForEach(0..<4, id: \.self) { _ in Rectangle().fill(Color(white: 0.85)).frame(height: 1) }
                        }
                        .padding(.top, 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .offset(x: 234, y: 326)
            label("Notes", centre: 265)
            AppIcon {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(white: 0.4)).frame(width: 8, height: 8) }
                }
            }
            .offset(x: 328, y: 326)
            label("More", centre: 359)
        }
    }

    private func label(_ text: String, centre: CGFloat) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Picture.label).fixedSize()
            .frame(width: 100).offset(x: centre - 50, y: 396)
    }

    private func row(_ title: String, symbol: String, top: CGFloat, corners: (top: Bool, bottom: Bool)) -> some View {
        HStack {
            Text(title).font(.system(size: 18)).foregroundStyle(Picture.label)
            Spacer()
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Picture.label)
        }
        .padding(.horizontal, 21)
        .frame(width: 377, height: 54)
        .background(UnevenRoundedRectangle(topLeadingRadius: corners.top ? 13 : 0, bottomLeadingRadius: corners.bottom ? 13 : 0,
                                           bottomTrailingRadius: corners.bottom ? 13 : 0, topTrailingRadius: corners.top ? 13 : 0, style: .continuous)
            .fill(.white))
        .offset(x: 16, y: top)
    }
}

/// Step 3: the share sheet's "Apps" list in edit mode, Cra among the suggestions, the arrow
/// pointing up at its add button.
struct AppsListPicture: View {
    static let size = Picture.size

    var body: some View {
        Picture.frame {
            Color.black
            Text("9:58").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).offset(x: 55, y: 18)
            HStack(spacing: 6) {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(white: 0.45))
                Image(systemName: "wifi").font(.system(size: 15, weight: .semibold))
                Image(systemName: "battery.100").font(.system(size: 17))
            }
            .foregroundStyle(.white)
            .offset(x: 300, y: 19)
            // The sheet behind, pushed back, and the Apps sheet over it.
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(Color(white: 0.85)).frame(width: 374, height: 40).offset(x: 18, y: 52)
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Picture.groupedBackground).frame(width: 411, height: 606 - 62).offset(y: 62)
            Text("Apps").font(.system(size: 19, weight: .semibold)).foregroundStyle(Picture.label)
                .frame(width: 411).offset(y: 79)
            Text("Done").font(.system(size: 19, weight: .semibold)).foregroundStyle(Picture.systemBlue)
                .offset(x: 340, y: 79)
            Rectangle().fill(Color(white: 0.85)).frame(width: 411, height: 1).offset(y: 118)
            Text("Favorites").font(.system(size: 21, weight: .bold)).foregroundStyle(Picture.label).offset(x: 29, y: 145)
            group(top: 178, rows: [("Messages", .favorite)])
            Text("Suggestions").font(.system(size: 21, weight: .bold)).foregroundStyle(Picture.label).offset(x: 29, y: 275)
            group(top: 308, rows: [("News", .suggestion(toggle: false)), ("Reminders", .suggestion(toggle: true)), ("Cra", .suggestion(toggle: true))])
            Picture.arrow(from: CGPoint(x: 56, y: 640), to: CGPoint(x: 56, y: 500))
        }
    }

    private enum Kind { case favorite, suggestion(toggle: Bool) }

    private func group(top: CGFloat, rows: [(String, Kind)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    switch row.1 {
                    case .favorite:
                        Circle().fill(Picture.red).frame(width: 28, height: 28)
                            .overlay(Capsule().fill(.white).frame(width: 13, height: 3))
                    case .suggestion:
                        Circle().fill(Picture.green).frame(width: 28, height: 28)
                            .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
                    }
                    icon(row.0).padding(.leading, 18)
                    Text(row.0).font(.system(size: 19)).foregroundStyle(Picture.label).padding(.leading, 18)
                    Spacer()
                    if case .suggestion(true) = row.1 {
                        Capsule().fill(Picture.green).frame(width: 51, height: 31)
                            .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 27, height: 27).padding(.trailing, 2) }
                            .padding(.trailing, 21)
                    }
                }
                .padding(.leading, 19)
                .frame(height: 54)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 { Rectangle().fill(Color(white: 0.88)).frame(height: 1).padding(.leading, 113) }
                }
            }
        }
        .frame(width: 368)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white))
        .offset(x: 21, y: top)
    }

    @ViewBuilder private func icon(_ name: String) -> some View {
        switch name {
        case "Messages":
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(red: 0.2, green: 0.8, blue: 0.35))
                .overlay(Image(systemName: "message.fill").font(.system(size: 15)).foregroundStyle(.white)).frame(width: 30, height: 30)
        case "News":
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white)
                .overlay(Text("N").font(.system(size: 19, weight: .black)).foregroundStyle(Color(red: 0.96, green: 0.27, blue: 0.33)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(white: 0.9))).frame(width: 30, height: 30)
        case "Reminders":
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white)
                .overlay(VStack(spacing: 4) { ForEach([Color.blue, .red, .orange], id: \.self) { Circle().fill($0).frame(width: 4, height: 4) } }.offset(x: -6))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(white: 0.9))).frame(width: 30, height: 30)
        default:
            Image("LaunchMark").resizable().scaledToFit().padding(4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(white: 0.9))).frame(width: 30, height: 30)
        }
    }
}
