import CraCore
import SwiftUI

final class OnboardingModel: ObservableObject {
    let steps: [MobileOnboarding.Step]
    @Published var index = 0
    @Published var blocksAdsAndTrackers = true
    @Published var icon: MobileAppIcon
    var setIcon: (MobileAppIcon) -> Void = { _ in }
    /// Called with whether ads and trackers are to be blocked.
    var finish: (Bool) -> Void = { _ in }
    var openDefaultBrowserSettings: () -> Void = {}

    init(canUseAI: Bool, icon: MobileAppIcon) {
        steps = MobileOnboarding.steps(canUseAI: canUseAI)
        self.icon = icon
    }

    var step: MobileOnboarding.Step { steps[index] }

    func next() {
        if step == .defaultBrowser {
            openDefaultBrowserSettings()
            return finish(blocksAdsAndTrackers)
        }
        if index + 1 < steps.count {
            withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
        } else {
            finish(blocksAdsAndTrackers)
        }
    }
}

/// First launch. Arc Search's steps: a welcome on its vivid gradient, what the browser does,
/// Browse for Me, an icon for the home screen, blocking, and the default browser.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .id(model.step)
                Button(action: model.next) {
                    Text(MobileOnboarding.buttonTitle(for: model.step))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.step == .welcome ? Color(red: 0.2, green: 0.16, blue: 0.75) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(model.step == .welcome ? Color.white : Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("onboarding-next")
                if model.step == .defaultBrowser {
                    Button("Skip") { model.finish(model.blocksAdsAndTrackers) }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .accessibilityIdentifier("onboarding-skip")
                }
                Spacer().frame(height: 18)
            }
        }
    }

    /// The welcome is on the saturated blue-to-red gradient; the first Next fades it to the pale one.
    @ViewBuilder private var background: some View {
        if model.step == .welcome || model.step == .pinch {
            LinearGradient(colors: [Color(red: 0.13, green: 0.07, blue: 0.82), Color(red: 0.55, green: 0.13, blue: 0.78), Color(red: 0.95, green: 0.2, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [Color(red: 0.92, green: 0.91, blue: 0.99), Color(red: 0.99, green: 0.93, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            VStack(spacing: 28) {
                Image("LaunchMark").resizable().frame(width: 96, height: 96)
                Text(MobileOnboarding.welcomeTitle)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        case .meet:
            VStack(spacing: 22) {
                title(MobileOnboarding.meetTitle)
                VStack(spacing: 12) {
                    ForEach(MobileOnboarding.cards, id: \.title) { card in
                        HStack(spacing: 14) {
                            Image(systemName: card.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).font(.system(size: 17, weight: .semibold))
                                Text(card.detail).font(.system(size: 15)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
            }
        case .browseForMe:
            VStack(spacing: 22) {
                title(MobileOnboarding.browseTitle)
                VStack(spacing: 0) {
                    ForEach(Array(MobileOnboarding.sampleQueries.enumerated()), id: \.offset) { index, query in
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
                            Text(query).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("Browse for Me")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(index == 0 ? .white : .primary)
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(index == 0 ? Color.accentColor : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .frame(height: 50)
                        .opacity(1 - Double(index) * 0.15)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 24)
            }
        case .pinch:
            VStack(spacing: 22) {
                Text("\(Text("Pinch").italic()) to summarize any web page")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .accessibilityIdentifier("onboarding-title")
                PinchDemo()
            }
        case .icon:
            VStack(spacing: 24) {
                title(MobileOnboarding.iconTitle)
                AppIconGrid(selected: model.icon) { icon in
                    model.icon = icon
                    model.setIcon(icon)
                }
                .padding(.horizontal, 40)
            }
        case .blocking:
            VStack(spacing: 24) {
                title(MobileOnboarding.blockingTitle)
                Toggle(isOn: $model.blocksAdsAndTrackers) {
                    HStack(spacing: 14) {
                        SettingIcon(symbol: "hand.raised.fill", color: Color(red: 1, green: 0.22, blue: 0.33))
                        Text(MobileOnboarding.blockingSwitch).font(.system(size: 17, weight: .medium))
                    }
                }
                .padding(16)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 24)
                .accessibilityIdentifier("onboarding-blocking")
            }
        case .defaultBrowser:
            VStack(spacing: 16) {
                Image(systemName: "safari.fill").font(.system(size: 52)).foregroundStyle(Color.accentColor)
                title(MobileOnboarding.defaultBrowserTitle)
                Text(MobileOnboarding.defaultBrowserDetail).font(.system(size: 17)).foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .accessibilityIdentifier("onboarding-title")
    }
}

/// The app's icons in a grid with a radio mark under each: onboarding's step and Settings' picker.
struct AppIconGrid: View {
    let selected: MobileAppIcon
    let pick: (MobileAppIcon) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 2), spacing: 22) {
            ForEach(MobileAppIcon.allCases) { icon in
                Button { pick(icon) } label: {
                    VStack(spacing: 10) {
                        Image(icon.previewName)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        Image(systemName: icon == selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(icon == selected ? Color.accentColor : Color.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.label)
                .accessibilityIdentifier("icon-\(icon.rawValue)")
                .accessibilityAddTraits(icon == selected ? .isSelected : [])
            }
        }
    }
}

/// Settings ▸ App Icon.
struct AppIconPicker: View {
    @State private var selected = MobileAppIcon(alternateName: UIApplication.shared.alternateIconName)

    var body: some View {
        ScrollView {
            AppIconGrid(selected: selected) { icon in
                selected = icon
                AppIconPicker.apply(icon)
            }
            .padding(40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func apply(_ icon: MobileAppIcon) {
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != icon.alternateName else { return }
        UIApplication.shared.setAlternateIconName(icon.alternateName)
    }
}

/// Onboarding's Pinch to Summarize step acted out on a loop, after 60fps.design's clip: two
/// fingers pinch a page, it folds flat and comes back as a small card, "Summarizing for you…",
/// then the summary and a check mark.
struct PinchDemo: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5.2)
            frame(t: t)
        }
        .frame(width: 250, height: 380)
        .accessibilityHidden(true)
    }

    private func frame(t: Double) -> some View {
        let pinch = min(1, max(0, (t - 0.3) / 1.0))
        let folding = t > 1.3 && t < 1.7
        let card = t >= 1.7
        let summary = min(1, max(0, (t - 2.6) / 0.6))
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(red: 0.8, green: 0.75, blue: 0.95))
            RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.white, lineWidth: 6)
            if !card {
                page.scaleEffect(x: 1, y: folding ? 0.04 : 1, anchor: .center)
                    .padding(10)
                    .animation(.easeIn(duration: 0.3), value: folding)
            } else {
                VStack(spacing: 10) {
                    page.frame(width: 230, height: 360).scaleEffect(0.45).frame(width: 104, height: 162)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .padding(.top, 30)
                    if summary < 1 {
                        Text("Summarizing for you…").font(.system(size: 11)).foregroundStyle(.black.opacity(0.55))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<5, id: \.self) { line in
                            RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.5)).frame(width: line == 4 ? 120 : 190, height: 5)
                        }
                    }
                    .opacity(summary)
                }
            }
            if !card {
                Circle().fill(Color(red: 0.35, green: 0.35, blue: 0.95).opacity(0.8)).frame(width: 28, height: 28)
                    .position(x: 190 - 60 * pinch, y: 120 + 60 * pinch)
                Circle().fill(Color(red: 1, green: 0.4, blue: 0.55).opacity(0.8)).frame(width: 28, height: 28)
                    .position(x: 70 + 60 * pinch, y: 280 - 60 * pinch)
            }
            if card {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white, Color.accentColor)
                    .offset(y: -50)
                    .opacity(summary)
            }
        }
    }

    /// A page: a dark picture with its headline, then a title and lines of text.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(white: 0.1), Color(white: 0.22)], startPoint: .top, endPoint: .bottom)
                Text("The night sky,\nexplained").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            }
            .frame(height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text("A field guide to the stars").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                ForEach(0..<9, id: \.self) { line in
                    RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.25)).frame(width: line % 3 == 2 ? 140 : 200, height: 4)
                }
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
