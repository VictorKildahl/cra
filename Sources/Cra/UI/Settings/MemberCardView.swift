import AppKit
import SwiftUI

/// Settings' first tab, laid out as Arc 1.172.2's Account tab (Victor, 12 Nov 2026): the default-browser banner over
/// the window, the member card on the left with Share, Save and Copy under it, and on the right the cards: Sync where
/// Arc has the account and Sync Sidebar, then "Share Cra with a Friend" where Arc has "Gift Arc to a Friend".
struct SyncPane: View {
    private let system = SystemIntegration.shared
    @State private var sharing = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if !system.isDefaultBrowser {
                    DefaultBrowserBanner(prompting: system.isPromptingDefault) {
                        Task { await system.makeDefaultBrowser() }
                    }
                    .padding(.top, 14)
                }
                HStack(alignment: .top, spacing: 34) {
                    MemberCardColumn()
                        .frame(width: MemberCardFace.size.width)
                    VStack(alignment: .leading, spacing: 0) {
                        SyncSection()
                        ShareCraCard { sharing = true }.padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, SettingsMetrics.paneBottom)
        }
        .scrollIndicators(.automatic)
        .onAppear { system.refresh() }
        .sheet(isPresented: $sharing) { ShareCraSheet() }
    }
}

/// Arc's "Arc isn't your default browser." pill with its blue "Make Arc your default" button.
private struct DefaultBrowserBanner: View {
    let prompting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Cra isn’t your default browser.").font(.system(size: 13))
            Button(action: action) {
                Label(prompting ? "Confirm in the Dialog…" : "Make Cra your default", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(Color.settingsBlue))
            }
            .buttonStyle(.plain)
            .disabled(prompting)
        }
        .padding(.leading, 16).padding(.trailing, 6).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.12)))
    }
}

// MARK: - The card

/// The card and Arc's three buttons under it: share it, save it as a picture, copy it.
private struct MemberCardColumn: View {
    @State private var copied = false

    private var card: MemberCard {
        MemberCard(fullName: NSFullUserName(), since: Self.joined, now: Date())
    }

    /// The day Cra's data folder was made: the first time Cra ran on this Mac with this profile.
    private static var joined: Date {
        (try? AppPaths.supportDir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
    }

    var body: some View {
        let card = card
        VStack(spacing: 18) {
            MemberCardFace(card: card)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            HStack(spacing: 34) {
                if let image = Self.render(card) {
                    ShareLink(item: Image(nsImage: image), message: Text(ShareCra.text),
                              preview: SharePreview("My Cra card", image: Image(nsImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share your card")
                }
                Button { save(card) } label: { Image(systemName: "square.and.arrow.down") }
                    .help("Save your card as a picture")
                Button { copy(card) } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help("Copy your card")
            }
            .buttonStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
        }
    }

    @MainActor static func render(_ card: MemberCard) -> NSImage? {
        let renderer = ImageRenderer(content: MemberCardFace(card: card).environment(\.colorScheme, .light))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func save(_ card: MemberCard) {
        guard let image = Self.render(card), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My Cra Card.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }

    private func copy(_ card: MemberCard) {
        guard let image = Self.render(card) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

/// The card itself, 240 × 360 pt like Arc's: a cream card, a picture of Cra's mark on the app icon's sand, the
/// member's name and nickname, the stamps, and a foot with the date they joined.
struct MemberCardFace: View {
    static let size = CGSize(width: 240, height: 360)
    static let cream = Color(.sRGB, red: 1, green: 0.99, blue: 0.92)
    static let blue = Color(.sRGB, red: 0x3f / 255, green: 0x6d / 255, blue: 0xf5 / 255)
    static let coral = Color(.sRGB, red: 0xf0 / 255, green: 0x57 / 255, blue: 0x4f / 255)
    static let green = Color(.sRGB, red: 0x4f / 255, green: 0xbe / 255, blue: 0x7e / 255)

    let card: MemberCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
            Text(card.name)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(theme.deep)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.top, 18)
            Text(card.nickname)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.deep)
                .padding(.top, 2)
            Spacer(minLength: 0)
            HStack(spacing: -6) {
                ForEach(Array(card.stamps.enumerated()), id: \.offset) { i, stamp in
                    // Older stamps fade, as Arc's first anniversary is paler than its second.
                    MemberStamp(stamp: stamp, color: theme.deep.opacity(i == card.stamps.count - 1 ? 1 : 0.5))
                        .rotationEffect(.degrees(i % 2 == 0 ? -8 : 6))
                }
            }
            .padding(.bottom, 10)
            HStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    Text("CRA").font(.system(size: 8, weight: .bold)).padding(.horizontal, 6)
                    Hatch().stroke(theme.deep.opacity(0.7), lineWidth: 0.6).frame(width: 12)
                        .clipped()
                        .overlay(Rectangle().stroke(theme.deep, lineWidth: 1))
                    Text(card.since.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: 8, weight: .bold)).padding(.horizontal, 6)
                }
                .frame(height: 15)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(theme.deep, lineWidth: 1))
                Spacer(minLength: 4)
                Text("OPEN\nSOURCE").font(.system(size: 9, weight: .regular, design: .serif))
                    .multilineTextAlignment(.trailing).lineSpacing(-2)
            }
            .foregroundStyle(theme.deep)
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.cream))
        .accessibilityElement(children: .combine)
    }

    /// Arc's card shows a gradient with a wavy bite out of it, the cream showing through. Cra's bite is its own mark:
    /// the C's four ribbons, large and cropped by the right and bottom edges, each cut 72 % through the member's
    /// gradient so they overlap like the mark's translucent segments (Victor picked this, variant D, 12 Nov 2026).
    private var art: some View {
        LinearGradient(colors: [theme.light, theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
            .mask {
                ZStack {
                    Rectangle()
                    SegmentedC().blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .frame(height: 192)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    var theme: MemberCardTheme { MemberCardTheme.all[card.theme % MemberCardTheme.all.count] }
}

/// A member's colours: the gradient behind the C, from its light corner to its deep one, and the deep one for the
/// name and the ink. Pairs of Cra's mark colours (brand/README.md), the light end a tint of the deep one's neighbour.
struct MemberCardTheme {
    let light: Color
    let deep: Color

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// Coral, blue, green, sunset: MemberCard.themeCount of them.
    static let all = [
        MemberCardTheme(light: rgb(0xf7c2a6), deep: rgb(0xe23d2e)),
        MemberCardTheme(light: rgb(0xb9cbff), deep: rgb(0x2f5be8)),
        MemberCardTheme(light: rgb(0xd3efb9), deep: rgb(0x23945a)),
        MemberCardTheme(light: rgb(0xfbe3a0), deep: rgb(0xe8692a)),
    ]
}

/// Cra's C as the mark draws it (brand/cra-segments.svg): four round-capped ribbons on one circle, the opening on the
/// right. Here very large, its centre right of and below the middle, and the ribbons overlapping by 10°.
private struct SegmentedC: View {
    static let center = CGPoint(x: 0.72, y: 0.70)
    static let radius: CGFloat = 0.50, width: CGFloat = 0.27
    static let opening = 38.0, overlap = 10.0, cut = 0.72

    var body: some View {
        GeometryReader { g in
            let span = (360 - 2 * Self.opening + 3 * Self.overlap) / 4
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let start = Self.opening + Double(i) * (span - Self.overlap)
                    Ribbon(start: start, end: start + span)
                        .stroke(.black.opacity(Self.cut), style: StrokeStyle(lineWidth: g.size.height * Self.width, lineCap: .round))
                }
            }
        }
    }

    private struct Ribbon: Shape {
        let start: Double, end: Double
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: rect.minX + rect.width * SegmentedC.center.x, y: rect.minY + rect.height * SegmentedC.center.y),
                     radius: rect.height * SegmentedC.radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
            return p
        }
    }
}

/// A round stamp in the style of Arc's anniversary stamps: two rings and what it stands for in the middle.
private struct MemberStamp: View {
    let stamp: MemberCard.Stamp
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(MemberCardFace.cream)
            Circle().stroke(color, lineWidth: 1.5)
            Circle().inset(by: 4).stroke(color, style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.5]))
            VStack(spacing: 0) {
                switch stamp {
                case .early(let year):
                    Text("EARLY").font(.system(size: 6.5, weight: .heavy))
                    Text("’\(year % 100)").font(.system(size: 13, weight: .heavy, design: .rounded))
                case .months(let n):
                    Text("\(n)").font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(n == 1 ? "MONTH" : "MONTHS").font(.system(size: 5.5, weight: .heavy))
                case .anniversary(let n):
                    Text("\(n)").font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(n == 1 ? "YEAR" : "YEARS").font(.system(size: 5.5, weight: .heavy))
                }
            }
            .foregroundStyle(color)
        }
        .frame(width: 40, height: 40)
    }
}

/// The diagonal lines in the card's date box.
private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 2.5
        }
        return p
    }
}

// MARK: - Sharing Cra

/// Arc's "Gift Arc to a Friend" card. Arc unlocks icons for gifts it counts on its server; Cra counts nothing, so the
/// card only asks.
private struct ShareCraCard: View {
    let share: () -> Void

    var body: some View {
        SettingsCard {
            SettingsCardRow {
                Text("Share Cra with a Friend").font(.system(size: 13))
            } trailing: {
                Button(action: share) { Label("Share Cra", systemImage: "gift") }
            }
            SettingsCardDivider()
            Text("Cra is free and open source, and it grows by word of mouth. Know someone who’d like it? Send them the link.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SettingsMetrics.cardRowInset)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Arc's "Share Arc with a friend" sheet: the mark, a big title, and a ticket with the message and the link over a
/// COPY LINK button. Cra's adds the system's share menu under the ticket (Messages, Mail and the rest).
struct ShareCraSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private static let background = Color(.sRGB, red: 0.11, green: 0.11, blue: 0.12)
    private static let ticket = Color(.sRGB, red: 0.13, green: 0.19, blue: 0.2)
    private static let green = MemberCardFace.green

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            BrandMark(size: 64).padding(.top, 4)
            Text("Share Cra\nwith a friend")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .multilineTextAlignment(.center).lineSpacing(-6)
                .foregroundStyle(.white)
                .padding(.top, 14)
            Text("Thanks for sharing Cra!").font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                .padding(.top, 14)
            ticket.padding(.top, 26)
            ShareLink(item: URL(string: ShareCra.link)!, message: Text(ShareCra.message)) {
                Label("Share…", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 18)
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 26)
        .frame(width: 470)
        .background(Self.background)
        .environment(\.colorScheme, .dark)
    }

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(ShareCra.message)
                Text(ShareCra.link).textSelection(.enabled)
            }
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 24)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ShareCra.link, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Text(copied ? "COPIED!" : "COPY LINK")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.green))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .padding(.bottom, 4)
            .background(Self.green.opacity(0.75))
        }
        .background(Self.ticket)
        .clipShape(TicketEdges())
        .overlay(TicketEdges().stroke(Self.green, lineWidth: 1.5))
        .frame(width: 340)
    }
}

/// A ticket's torn top and bottom: a zigzag across each end, straight sides.
private struct TicketEdges: Shape {
    var tooth: CGFloat = 9
    var depth: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int((rect.width / tooth).rounded()))
        let w = rect.width / CGFloat(n)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        for i in 0..<n {
            let x = rect.minX + CGFloat(i) * w
            p.addLine(to: CGPoint(x: x + w / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: x + w, y: rect.minY + depth))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        for i in 0..<n {
            let x = rect.maxX - CGFloat(i) * w
            p.addLine(to: CGPoint(x: x - w / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: x - w, y: rect.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}
