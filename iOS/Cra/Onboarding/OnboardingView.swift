import CraCore
import SwiftUI

final class OnboardingModel: ObservableObject {
    let steps: [MobileOnboarding.Step]
    @Published var index = 0
    @Published var blocksAdsAndTrackers = true
    @Published var icon: MobileAppIcon
    /// The Browse for Me, Pinch and blocking steps' phones: tried, working, done.
    @Published var progress: MockProgress = .idle
    /// The last step's inset sheet, "How to change your default browser".
    @Published var showsHowTo = false
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
        switch step {
        case .defaultBrowser:
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showsHowTo = true }
        case .blocking:
            // Arc Search checks the step off over its blurred phone before moving on.
            withAnimation { progress = .done }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.advance() }
        default:
            advance()
        }
    }

    func advance() {
        guard index + 1 < steps.count else { return finish(blocksAdsAndTrackers) }
        withAnimation(.easeInOut(duration: 0.45)) {
            progress = .idle
            index += 1
        }
    }

    func openSettings() {
        openDefaultBrowserSettings()
        finish(blocksAdsAndTrackers)
    }

    func later() { finish(blocksAdsAndTrackers) }
}

/// First launch, as Arc Search 1.49 does it (Victor's recording, 0:00–1:20): a welcome the
/// launch logo shrinks onto, what the browser does, Browse for Me and Pinch tried on a phone,
/// an icon for the home screen, blocking shown on a page, and the default browser. All but the
/// last on the vivid gradient.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    // Start with a two-line heading so the first demo frame already fits.
    @State private var headingHeight: CGFloat = 66
    @State private var iconTitleHeight: CGFloat = 0
    @State private var iconGridHeight: CGFloat = 0

    private var tried: Bool { model.progress == .done }

    var body: some View {
        ZStack {
            VividBackdrop().ignoresSafeArea().opacity(MobileOnboarding.isVivid(model.step) ? 1 : 0)
            PaleBackdrop().ignoresSafeArea().opacity(MobileOnboarding.isVivid(model.step) ? 0 : 1)
            GeometryReader { geometry in
                // Geometry offers the safe content area; the mock follows the whole window's aspect.
                let insets = geometry.safeAreaInsets
                let window = CGSize(width: geometry.size.width + insets.leading + insets.trailing,
                                    height: geometry.size.height + insets.top + insets.bottom)
                let mock = MobileOnboarding.mock(window: window, safeLeft: insets.leading, safeRight: insets.trailing)
                layout(in: geometry, mock: mock)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: MobileOnboarding.isVivid(model.step))
    }

    private func layout(in geometry: GeometryProxy, mock: MobileOnboarding.Mock) -> some View {
        ZStack {
            content(in: geometry, mock: mock)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 30)), removal: .opacity))
                .id(model.step)
            VStack(spacing: 0) {
                Spacer()
                let next = Button(action: model.next) {
                    Text(MobileOnboarding.buttonTitle(for: model.step))
                        .scaledFont(size: 17, weight: .medium, relativeTo: .body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(OnboardingColors.button, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .opacity(MobileOnboarding.showsNext(model.step, tried: tried) && model.progress != .working ? 1 : 0)
                .disabled(!MobileOnboarding.showsNext(model.step, tried: tried) || (model.step == .blocking && tried))
                .accessibilityIdentifier("onboarding-next")
                // No wider than SheetHost's content on a wide screen (the open iPhone Duo, #866); a phone is narrower anyway.
                if mock.shape == .phone {
                    next.frame(maxWidth: MobileScreenClass.contentCap)
                } else {
                    next.frame(maxWidth: min(mock.size.width, MobileScreenClass.contentCap))
                }
                if model.step == .defaultBrowser {
                    Button(MobileOnboarding.defaultBrowserSkip) { model.later() }
                        .scaledFont(size: 17, weight: .medium, relativeTo: .body)
                        .foregroundStyle(OnboardingColors.ink)
                        .padding(.top, 16)
                        .accessibilityIdentifier("onboarding-skip")
                }
                Spacer().frame(height: 18)
            }
            if MobileOnboarding.showsSkip(model.step, tried: tried) && model.progress == .idle {
                Button("Skip") { model.advance() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityIdentifier("onboarding-step-skip")
            }
            if model.showsHowTo {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { model.later() }
                HowToSheet(icon: model.icon, open: model.openSettings, later: model.later)
                    .transition(.move(edge: .bottom))
            }
        }
    }

    @ViewBuilder private func content(in geometry: GeometryProxy, mock: MobileOnboarding.Mock) -> some View {
        switch model.step {
        case .welcome:
            WelcomeStep()
        case .meet:
            VStack(spacing: 26) {
                OnboardingTitle(text: MobileOnboarding.meetTitle)
                VStack(spacing: 10) {
                    ForEach(Array(MobileOnboarding.cards.enumerated()), id: \.offset) { index, card in
                        HStack(spacing: 12) {
                            Image(systemName: card.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Self.cardColors[index % Self.cardColors.count], in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.title).scaledFont(size: 15, weight: .bold, relativeTo: .body).foregroundStyle(OnboardingColors.pillText)
                                Text(card.detail).scaledFont(size: 14, weight: .regular, relativeTo: .subheadline).foregroundStyle(OnboardingColors.pillDetail)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .environment(\.colorScheme, .light)
            }
            .padding(.top, 50)
        case .browseForMe:
            demo(title: MobileOnboarding.browseTitle, in: geometry, mock: mock) {
                BrowseDemo(mock: mock, progress: $model.progress)
            }
        case .pinch:
            demo(title: MobileOnboarding.pinchTitle, in: geometry, mock: mock) {
                PinchDemo(mock: mock, progress: $model.progress)
            }
        case .icon:
            let scale = MobileOnboarding.fitScale(available: geometry.size.height, topInset: geometry.safeAreaInsets.top,
                                                  bottomInset: geometry.safeAreaInsets.bottom, heading: iconTitleHeight,
                                                  scalable: iconGridHeight, topPadding: 50, spacing: 30, bottomReserved: 18 + 50 + 16)
            VStack(spacing: 30) {
                OnboardingTitle(text: MobileOnboarding.iconTitle)
                    .fixedSize(horizontal: false, vertical: scale < 1)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { iconTitleHeight = $0 }
                AppIconGrid(icons: MobileAppIcon.onboardingChoices, selected: model.icon, onVivid: true, scale: scale) { icon in
                    model.icon = icon
                    model.setIcon(icon)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { iconGridHeight = $0 }
                .frame(height: scale < 1 ? iconGridHeight * scale : nil)
                .padding(.horizontal, 60)
            }
            .padding(.top, 50)
        case .blocking:
            demo(title: MobileOnboarding.blockingTitle, in: geometry, mock: mock) {
                BlockingDemo(mock: mock, blocks: $model.blocksAdsAndTrackers)
                    .blur(radius: model.progress == .done ? 6 : 0)
            }
        case .defaultBrowser:
            VStack(spacing: 18) {
                Spacer().frame(height: 110)
                Image(model.icon.previewName)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .accessibilityHidden(true)
                Text(MobileOnboarding.defaultBrowserTitle)
                    .scaledFont(size: 42, weight: .heavy, relativeTo: .largeTitle)
                    .foregroundStyle(OnboardingColors.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                    .accessibilityIdentifier("onboarding-title")
                Text(MobileOnboarding.defaultBrowserBody)
                    .scaledFont(size: 15, weight: .regular, relativeTo: .body)
                    .foregroundStyle(Color(white: 0.2))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
        }
    }

    private func demo<Picture: View>(title: String, in geometry: GeometryProxy, mock: MobileOnboarding.Mock, @ViewBuilder picture: () -> Picture) -> some View {
        let scale = MobileOnboarding.fitScale(available: geometry.size.height, topInset: geometry.safeAreaInsets.top,
                                              bottomInset: geometry.safeAreaInsets.bottom, heading: headingHeight,
                                              scalable: mock.size.height)
        return VStack(spacing: 24) {
            StepHeading(title: title, progress: model.progress)
                .fixedSize(horizontal: false, vertical: scale < 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headingHeight = $0 }
            Group {
                if scale < 1 {
                    picture()
                        .scaleEffect(scale)
                        .frame(width: mock.size.width * scale, height: mock.size.height * scale)
                } else {
                    picture()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding-mock")
            .accessibilityValue(mock.shape.rawValue)
        }
        .padding(.top, 40)
    }

    /// The four pills' round icons: red, purple, blue, cyan.
    private static let cardColors = [Color(red: 1, green: 0.27, blue: 0.33), Color(red: 0.6, green: 0.3, blue: 0.95),
                                     Color(red: 0.2, green: 0.3, blue: 0.95), Color(red: 0.1, green: 0.7, blue: 0.95)]
}

/// The welcome: the launch logo shrinks to the top while "Get what you want *twice* as fast."
/// comes up over the lower part of the screen.
private struct WelcomeStep: View {
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("LaunchMark")
                    .resizable()
                    .frame(width: 66, height: 66)
                    .scaleEffect(settled ? 1 : 4.5)
                    .position(x: settled ? proxy.size.width / 2 : proxy.size.width * 0.3,
                              y: settled ? 70 : proxy.size.height * 0.82)
                    .accessibilityHidden(true)
                OnboardingTitle(text: MobileOnboarding.welcomeTitle, size: 36)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.7)
                    .opacity(settled ? 1 : 0)
            }
        }
        .onAppear {
            guard !settled else { return }
            if reduceMotion { settled = true; return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.2)) { settled = true }
        }
    }
}

/// "How to change your default browser": a white card inset from the screen's edges, the three
/// steps in Settings, "Open Cra in Settings" and "Maybe later" (the recording, 1:14).
private struct HowToSheet: View {
    let icon: MobileAppIcon
    let open: () -> Void
    let later: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Text(MobileOnboarding.howToTitle)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(OnboardingColors.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding-howto")
                Text(MobileOnboarding.howToBody)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(MobileOnboarding.defaultBrowserSteps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 12) {
                            stepIcon(index).frame(width: 28, height: 28)
                            Text(step).font(.system(size: 16)).foregroundStyle(.black)
                        }
                        .frame(height: 46)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 6)
                Button(action: open) {
                    Text(MobileOnboarding.howToOpen).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(OnboardingColors.button, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding-open-settings")
                Button(MobileOnboarding.howToLater, action: later)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OnboardingColors.ink)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("onboarding-later")
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 18)
            .background(.white, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private func stepIcon(_ index: Int) -> some View {
        switch index {
        case 0:
            Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color(white: 0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case 2:
            Image(icon.previewName).resizable().clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        default:
            Color.clear
        }
    }
}

/// The app's icons in a grid with a radio mark under each: onboarding's step (Cra's own four) and Settings'
/// picker (every icon, scrolling).
struct AppIconGrid: View {
    var icons = MobileAppIcon.allCases
    let selected: MobileAppIcon
    /// On onboarding's gradient: white radios, and a white frame round the picked icon.
    var onVivid = false
    var scale: CGFloat = 1
    let pick: (MobileAppIcon) -> Void

    /// The widest the grid gets on an iPhone (Settings' picker on a Pro Max: 440 pt less its
    /// padding). An iPad's wider sheet keeps that size, centred, instead of growing the icons
    /// until the second row falls off the sheet.
    static let maxWidth: CGFloat = 360

    var body: some View {
        Group {
            if scale < 1 {
                grid.scaleEffect(scale)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 2), spacing: 22) {
            ForEach(icons) { icon in
                Button { pick(icon) } label: {
                    VStack(spacing: 10) {
                        Image(icon.previewName)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(onVivid ? 4 : 0)
                            .overlay {
                                if onVivid && icon == selected {
                                    RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(.white, lineWidth: 3)
                                }
                            }
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        if onVivid {
                            Image(systemName: icon == selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(icon == selected ? OnboardingColors.indigo : .white.opacity(0.6), .white)
                        } else {
                            Image(systemName: icon == selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(icon == selected ? Color.accentColor : Color.secondary.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.label)
                .accessibilityIdentifier("icon-\(icon.rawValue)")
                .accessibilityAddTraits(icon == selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: Self.maxWidth)
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

/// A fixed design size that grows and shrinks with the phone's text size (Dynamic Type), as
/// Arc Search's onboarding does since 1.22.2.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style))
    }
}
