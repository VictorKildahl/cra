import CraCore
import SwiftUI

final class SummaryModel: ObservableObject {
    enum State: Equatable {
        case working
        case done(MobileSummary.Answer)
        case failed
    }

    @Published var state: State = .working
    let title: String
    let favicon: UIImage?
    let snapshot: UIImage?
    /// The page's address, named under a copied or shared summary.
    var address: String?
    var close: () -> Void = {}
    var share: (String) -> Void = { _ in }

    init(title: String, favicon: UIImage?, snapshot: UIImage?) {
        self.title = title
        self.favicon = favicon
        self.snapshot = snapshot
    }

    /// The finished summary as text, or nil while it is being written.
    var text: String? {
        guard case .done(let answer) = state else { return nil }
        return answer.plainText(title: title, address: address)
    }
}

/// Arc Search's summary screen: the page as a small folded card under its title, the summary
/// below it, and a footer that says who wrote it, with the close button.
struct SummaryView: View {
    @ObservedObject var model: SummaryModel
    /// The card unfolds into place as the screen comes in (off with Reduce Motion).
    var unfolds = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            FaviconView(image: model.favicon).frame(width: 16, height: 16)
                            Text(model.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        FoldedPageCard(snapshot: model.snapshot, unfolds: unfolds)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    content
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 90)
            }
            footer
        }
    }

    /// Dark: Arc Search 1.49's (Victor's recording, 2:34): dark plum above and below, a raspberry
    /// glow on the left, magenta in the middle, blue-violet on the right. Light: pale lavender.
    @ViewBuilder private var backdrop: some View {
        if scheme == .dark {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    Color(red: 0.18, green: 0.14, blue: 0.21)
                    RadialGradient(colors: [Color(red: 0.64, green: 0.32, blue: 0.4), .clear], center: .center, startRadius: 0, endRadius: w * 0.75)
                        .frame(width: w * 1.5, height: w * 1.5).position(x: w * 0.05, y: h * 0.42)
                    RadialGradient(colors: [Color(red: 0.59, green: 0.29, blue: 0.53).opacity(0.85), .clear], center: .center, startRadius: 0, endRadius: w * 0.55)
                        .frame(width: w * 1.1, height: w * 1.1).position(x: w * 0.5, y: h * 0.47)
                    RadialGradient(colors: [Color(red: 0.23, green: 0.19, blue: 0.54), .clear], center: .center, startRadius: 0, endRadius: w * 0.6)
                        .frame(width: w * 1.2, height: w * 1.2).position(x: w * 1.0, y: h * 0.4)
                }
            }
        } else {
            LinearGradient(colors: [Color(red: 0.89, green: 0.87, blue: 0.98), Color(red: 0.98, green: 0.89, blue: 0.93)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .working:
            Text("Summarizing for you...")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("summary-working")
        case .failed:
            Text("This page has too little text to summarize.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("summary-failed")
        case .done(let answer):
            if !answer.overview.isEmpty {
                Text(answer.overview).font(.system(size: 17)).lineSpacing(3).foregroundStyle(.primary.opacity(0.72))
                    .accessibilityIdentifier("summary-overview")
            }
            ForEach(answer.sections) { section in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color.accentColor).frame(width: 26, height: 26)
                        .overlay(Image(systemName: Self.symbol(section.symbol)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary.opacity(0.85))
                        Text(section.body).font(.system(size: 17)).lineSpacing(3).foregroundStyle(.primary.opacity(0.72))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// The model's symbol when the system has one by that name, a sparkle otherwise.
    private static func symbol(_ name: String?) -> String {
        guard let name, UIImage(systemName: name) != nil else { return "sparkle" }
        return name
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image("LaunchMark").resizable().frame(width: 22, height: 22)
            Text(MobileSummary.credit).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            if let text = model.text {
                footerButton("doc.on.doc", label: "Copy", id: "summary-copy") {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                footerButton("square.and.arrow.up", label: "Share", id: "summary-share") { model.share(text) }
            }
            Button(action: model.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("summary-close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func footerButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The page folded small: its top as a card, and above it a thin strip showing the same top
/// upside down, as if the page were folded back there.
private struct FoldedPageCard: View {
    let snapshot: UIImage?
    var unfolds = false
    @State private var unfolded = false

    var body: some View {
        card
            // From the strip at mid-height: unfolds about 75 % wide, then rises with a slight tilt
            // that straightens as it settles (App Store preview, 14.5–14.8 s).
            .rotation3DEffect(.degrees(unfolds && !unfolded ? 80 : 0), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
            .rotationEffect(.degrees(unfolds && !unfolded ? -4 : 0))
            .scaleEffect(unfolds && !unfolded ? 1.3 : 1)
            .offset(y: unfolds && !unfolded ? 180 : 0)
            .onAppear {
                guard unfolds else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { unfolded = true }
            }
    }

    private var card: some View {
        VStack(spacing: 0) {
            page(width: 218).frame(width: 218, height: 16, alignment: .top).clipped()
                .scaleEffect(x: 1, y: -1)
                .overlay(Color.black.opacity(0.18))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            page(width: 236).frame(width: 236, height: 240, alignment: .top).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        }
    }

    /// The page picture `width` wide, starting below the strip the status bar covers.
    @ViewBuilder private func page(width: CGFloat) -> some View {
        if let snapshot, snapshot.size.width > 0 {
            let scale = width / snapshot.size.width
            Image(uiImage: snapshot).resizable()
                .frame(width: width, height: snapshot.size.height * scale)
                .offset(y: -52 * scale)
        } else {
            Color(.systemBackground)
        }
    }
}
