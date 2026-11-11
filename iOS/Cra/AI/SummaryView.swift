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
    var close: () -> Void = {}

    init(title: String, favicon: UIImage?, snapshot: UIImage?) {
        self.title = title
        self.favicon = favicon
        self.snapshot = snapshot
    }
}

/// Arc Search's summary screen: the page as a small folded card under its title, the summary
/// below it, and a footer that says who wrote it, with the close button.
struct SummaryView: View {
    @ObservedObject var model: SummaryModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: scheme == .dark ? [Color(red: 0.13, green: 0.12, blue: 0.2), Color(red: 0.2, green: 0.12, blue: 0.18)]
                                                   : [Color(red: 0.89, green: 0.87, blue: 0.98), Color(red: 0.98, green: 0.89, blue: 0.93)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            FaviconView(image: model.favicon).frame(width: 16, height: 16)
                            Text(model.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        FoldedPageCard(snapshot: model.snapshot)
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
}

/// The page folded small: its top as a card, and above it a thin strip showing the same top
/// upside down, as if the page were folded back there.
private struct FoldedPageCard: View {
    let snapshot: UIImage?

    var body: some View {
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
