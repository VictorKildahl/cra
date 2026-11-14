import CraCore
import SwiftUI

/// Arc Search 1.49's onboarding colours, sampled from Victor's recording.
enum OnboardingColors {
    static let button = Color(red: 0.208, green: 0.31, blue: 1)          // #354FFF
    static let ink = Color(red: 0.212, green: 0.133, blue: 0.671)        // #3622AB, the last step's title
    static let indigo = Color(red: 0.2, green: 0.14, blue: 0.76)         // #3324C2
    static let blue = Color(red: 0.0, green: 0.2, blue: 0.86)            // #0033DB
    static let violet = Color(red: 0.52, green: 0.44, blue: 0.89)        // #8571E4
    static let red = Color(red: 1, green: 0.24, blue: 0.35)              // #FF3D5A
    static let pillText = Color(red: 0.11, green: 0.1, blue: 0.3)
    static let pillDetail = Color(red: 0.36, green: 0.36, blue: 0.54)
}

/// The vivid gradient behind every step but the last: deep indigo above, blue below, a violet
/// glow on the left and a pink-red one on the right that drift slowly, as in the recording.
struct VividBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(colors: [OnboardingColors.indigo, OnboardingColors.blue], startPoint: .top, endPoint: .bottom)
                    blob(OnboardingColors.violet, at: CGPoint(x: 0.12 + 0.05 * sin(t / 3.1), y: 0.5 + 0.06 * cos(t / 4.3)), radius: 0.55, in: size)
                    blob(OnboardingColors.red, at: CGPoint(x: 0.98 + 0.04 * cos(t / 3.7), y: 0.46 + 0.07 * sin(t / 2.9)), radius: 0.6, in: size)
                    blob(Color(red: 0.8, green: 0.45, blue: 0.75), at: CGPoint(x: 0.55 + 0.08 * sin(t / 5.3), y: 0.52 + 0.05 * sin(t / 3.3)), radius: 0.32, in: size)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, at point: CGPoint, radius: CGFloat, in size: CGSize) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: size.width * radius)
            .frame(width: size.width * radius * 2, height: size.width * radius * 2)
            .position(x: size.width * point.x, y: size.height * point.y)
            .blendMode(.normal)
    }
}

/// The last step's page: the vivid colours only along the top, fading into white.
struct PaleBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.white
            // Sampled down the recording's last step: indigo under the status bar, pink at a fifth of
            // the height, lavender at a third, white by half.
            LinearGradient(stops: [
                .init(color: OnboardingColors.indigo, location: 0),
                .init(color: Color(red: 0.79, green: 0.51, blue: 0.74), location: 0.4),
                .init(color: Color(red: 0.75, green: 0.72, blue: 0.9), location: 0.68),
                .init(color: .white, location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 470)
        }
        .accessibilityHidden(true)
    }
}

/// A phone in the steps: a white frame with round corners, its screen clipped inside. It runs
/// past the bottom of the step, under the button.
struct PhoneMock<Screen: View>: View {
    let screen: Screen

    init(@ViewBuilder screen: () -> Screen) { self.screen = screen() }

    var body: some View {
        screen
            .frame(width: 330, height: 640, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 6))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}

/// The status bar of a phone in the steps.
private struct MockStatusBar: View {
    var dark = false

    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 12, weight: .semibold))
            Spacer()
            Image(systemName: "cellularbars").font(.system(size: 10))
            Image(systemName: "wifi").font(.system(size: 10))
            Image(systemName: "battery.100").font(.system(size: 12))
        }
        .foregroundStyle(dark ? .white : .black)
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .frame(height: 36)
    }
}

/// Above a step's phone while it works: the title blurs behind a pulsing dot, then a check.
enum MockProgress: Equatable { case idle, working, done }

struct StepHeading: View {
    let title: String
    let progress: MockProgress
    @State private var pulse = false

    var body: some View {
        ZStack {
            OnboardingTitle(text: title)
                .blur(radius: progress == .idle ? 0 : 8)
                .opacity(progress == .done ? 0 : 1)
            if progress == .working {
                Circle().fill(.white.opacity(0.9)).frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.3 : 0.8)
                    .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { pulse = true } }
            }
            if progress == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OnboardingColors.indigo)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("onboarding-check")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: progress)
    }
}

/// A step's title: white, bold, with Arc Search's italic words.
struct OnboardingTitle: View {
    let text: String
    var size: CGFloat = 27

    var body: some View {
        Text(.init(text))
            .scaledFont(size: size, weight: .bold, relativeTo: .largeTitle)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .accessibilityLabel(MobileOnboarding.plain(text))
            .accessibilityIdentifier("onboarding-title")
    }
}

// MARK: Browse for Me

/// The Browse for Me step's phone: "Try it!" with an arrow onto the first question's chip over
/// a search sheet and its keyboard; a tap runs the question and the phone shows its page.
struct BrowseDemo: View {
    @Binding var progress: MockProgress

    var body: some View {
        PhoneMock {
            ZStack(alignment: .top) {
                if progress == .done {
                    result.transition(.opacity)
                } else {
                    sheet
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: progress)
    }

    private var sheet: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.08, blue: 0.45), OnboardingColors.red.opacity(0.8), OnboardingColors.blue],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                MockStatusBar(dark: true)
                Spacer().frame(height: 30)
                Text(MobileOnboarding.browseTryIt).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                VStack(spacing: 0) {
                    HStack {
                        Text("Search...").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.black.opacity(0.06), in: Capsule())
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    ForEach(Array(MobileOnboarding.sampleQueries.enumerated()), id: \.offset) { index, query in
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .medium))
                            Text(query).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button {
                                guard progress == .idle else { return }
                                progress = .working
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { progress = .done }
                            } label: {
                                Text("Browse for Me")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(index == 0 ? .white : .primary)
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(index == 0 ? OnboardingColors.button : Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Browse for Me: \(query)")
                            .accessibilityIdentifier(index == 0 ? "onboarding-try" : "onboarding-try-\(index)")
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                    }
                    MockKeyboard().padding(.top, 6)
                }
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            }
            TryItArrow().allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
    }

    /// What Browse for Me made of "things to do in paris", as the recording shows it.
    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockStatusBar()
            HStack {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
                Text(MobileOnboarding.sampleQueries[0]).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Color.black.opacity(0.05), in: Capsule())
            .padding(.horizontal, 12)
            Text("Top Attractions in Paris").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(red: 0.15, green: 0.25, blue: 0.75))
                .padding(.horizontal, 16)
            ForEach(Self.places, id: \.0) { place in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: place.2).font(.system(size: 11)).foregroundStyle(Color(red: 0.75, green: 0.3, blue: 0.2)).frame(width: 14)
                    (Text(place.0).bold().underline() + Text(" — " + place.1))
                        .font(.system(size: 11))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
            }
            Spacer()
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-browse-result")
    }

    private static let places = [
        ("Eiffel Tower", "A must-see landmark, the Eiffel Tower offers stunning views of Paris. Visitors can explore different levels, with the summit providing the most breathtaking panorama.", "building.columns.fill"),
        ("Louvre Museum", "Home to the Mona Lisa and countless other masterpieces, the Louvre is one of the world's largest and most visited art museums.", "paintpalette.fill"),
        ("Sainte-Chapelle", "Known for its stunning stained glass windows, this chapel is a masterpiece of Gothic architecture on the Île de la Cité.", "sparkles"),
        ("Château de Vincennes", "A medieval fortress located just outside Paris, offering a glimpse into France's royal past.", "shield.fill"),
        ("Musée de l'Orangerie", "Famous for Monet's Water Lilies, this museum offers a serene art experience in the Tuileries Garden.", "leaf.fill"),
    ]
}

/// The purple-to-pink line from "Try it!" onto the first chip, in the phone's own points.
private struct TryItArrow: View {
    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: size.width / 2, y: 84)
            let chip = CGPoint(x: size.width - 48, y: 256)
            let corners = MobileCoachMark.path(from: start, toChipTop: chip)
            var path = Path()
            path.move(to: corners.start)
            path.addQuadCurve(to: CGPoint(x: corners.start.x + 30, y: corners.firstTurn.y + 40), control: CGPoint(x: corners.start.x, y: corners.firstTurn.y + 40))
            path.addLine(to: CGPoint(x: corners.end.x - 20, y: corners.firstTurn.y + 40))
            path.addQuadCurve(to: corners.end, control: CGPoint(x: corners.end.x, y: corners.firstTurn.y + 40))
            path.move(to: CGPoint(x: corners.end.x - 5, y: corners.end.y - 7))
            path.addLine(to: corners.end)
            path.addLine(to: CGPoint(x: corners.end.x + 5, y: corners.end.y - 7))
            context.stroke(path, with: .linearGradient(Gradient(colors: [Color(red: 0.48, green: 0.33, blue: 1), Color(red: 1, green: 0.18, blue: 0.61)]),
                                                       startPoint: start, endPoint: chip),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A light keyboard, drawn small.
private struct MockKeyboard: View {
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(Array(row), id: \.self) { key in
                        Text(String(key)).font(.system(size: 12))
                            .frame(width: 26, height: 30)
                            .background(.white, in: RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 150, height: 30).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.bottom, 40)
        .background(Color(red: 0.82, green: 0.83, blue: 0.86))
        .accessibilityHidden(true)
    }
}

// MARK: Pinch to Summarize

/// The Pinch step's phone: President Kennedy's Moon speech, which a pinch folds into its
/// summary (the recording, 0:31). Two dots pinch on it until someone does.
struct PinchDemo: View {
    @Binding var progress: MockProgress
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PhoneMock {
            ZStack(alignment: .top) {
                if progress == .done {
                    summary.transition(.opacity)
                } else {
                    page.scaleEffect(scale, anchor: .center)
                    if progress == .idle && !reduceMotion { hint }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
        }
        .contentShape(Rectangle())
        .gesture(MagnificationGesture()
            .onChanged { value in
                guard progress == .idle else { return }
                scale = min(1, max(0.55, value))
            }
            .onEnded { value in
                guard progress == .idle else { return }
                if value < 0.85 { summarize() } else { withAnimation(.spring()) { scale = 1 } }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("We choose to go to the Moon")
        .accessibilityHint("Pinch to summarize")
        .accessibilityAction(named: "Summarize") { summarize() }
        .accessibilityIdentifier("onboarding-pinch-page")
        .environment(\.colorScheme, .light)
    }

    private func summarize() {
        guard progress == .idle else { return }
        withAnimation(.easeIn(duration: 0.25)) { scale = 0.5; progress = .working }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.4)) { progress = .done; scale = 1 }
        }
    }

    private var moon: some View {
        ZStack {
            Color.black.overlay {
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.72), Color(white: 0.42), Color(white: 0.16)], center: .init(x: 0.45, y: 0.6), startRadius: 4, endRadius: 200))
                    .frame(width: 420, height: 420)
                    .offset(y: -150)
            }
            .clipped()
            Text("We choose to\ngo to the Moon").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                .offset(y: 40)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 8) {
            moon.frame(height: 200).clipped().overlay(alignment: .top) { MockStatusBar(dark: true) }
            Text("Address at Rice University on the Nation's Space Effort").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                .padding(.horizontal, 14)
            Text("Delivered at Rice University on September 12, 1962").font(.system(size: 9)).foregroundStyle(.gray).padding(.horizontal, 14)
            Text("We meet at a college noted for knowledge, in a city noted for progress, in a state noted for strength, and we stand in need of all three, for we meet in an hour of change and challenge, in a decade of hope and fear, in an age of both knowledge and ignorance. The greater our knowledge increases, the greater our ignorance unfolds.\n\nDespite the striking fact that most of the scientists that the world has ever known are alive and working today, despite the fact that this Nation's own scientific manpower is doubling every 12 years in a rate of growth more than three times that of our population as a whole, despite that, the vast stretches of the unknown and the unanswered and the unfinished still far outstrip our collective comprehension.")
                .font(.system(size: 10)).foregroundStyle(.black.opacity(0.8)).padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .frame(width: 330)
    }

    private var hint: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4)
            let pinch = CGFloat(min(1, max(0, (t - 0.4) / 1.0)))
            ZStack {
                Circle().fill(Color(red: 0.35, green: 0.36, blue: 0.96).opacity(0.9)).frame(width: 30, height: 30)
                    .position(x: 210 - 40 * pinch, y: 330 + 30 * pinch)
                Circle().fill(Color(red: 1, green: 0.24, blue: 0.42).opacity(0.9)).frame(width: 30, height: 30)
                    .position(x: 120 + 40 * pinch, y: 420 - 30 * pinch)
            }
        }
        .allowsHitTesting(false)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockStatusBar()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("We choose to go to the Moon").font(.system(size: 8, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(6).background(Color.black)
                    Text("Address at Rice University on the Nation's Space Effort").font(.system(size: 8, weight: .bold)).padding(.horizontal, 6)
                }
                .frame(width: 130)
                .padding(.bottom, 6)
                .background(.white)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                Spacer()
            }
            Text("The speech, titled \u{201C}We choose to go to the Moon\u{201D}, was delivered by President John F. Kennedy at Rice University on September 12, 1962. It outlined the nation's space effort and the plan to land a man on the Moon before 1970.")
                .font(.system(size: 11)).foregroundStyle(.black).padding(.horizontal, 14)
            ForEach(Self.points, id: \.0) { point in
                VStack(alignment: .leading, spacing: 2) {
                    Label(point.0, systemImage: point.1).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.15, green: 0.25, blue: 0.75))
                    Text(point.2).font(.system(size: 10)).foregroundStyle(.black.opacity(0.75))
                }
                .padding(.horizontal, 14)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("onboarding-pinch-summary")
    }

    private static let points = [
        ("Space Exploration and Progress", "star.circle.fill", "President Kennedy emphasized the rapid pace of technological advancement, highlighting the achievements and advancements made in a relatively short period of time."),
        ("National Commitment to Space Exploration", "flag.circle.fill", "The speech conveyed the United States' commitment to space exploration, asserting its intention to lead the world in space exploration."),
        ("Economic and Scientific Impact", "chart.line.uptrend.xyaxis.circle.fill", "President Kennedy discussed the economic and scientific impact of the space effort."),
    ]
}

// MARK: Blocking

/// The blocking step's phone: a travel magazine's page that the switch clears of its ads
/// (the recording, 0:55; Arc Search's page is "Out West", this one is made up for Cra).
struct BlockingDemo: View {
    @Binding var blocks: Bool

    var body: some View {
        PhoneMock {
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    MockStatusBar()
                    if !blocks { topAd.transition(.move(edge: .top).combined(with: .opacity)) }
                    masthead
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Things to Do / ").foregroundStyle(.gray) + Text("Outdoors").bold().foregroundStyle(.black)
                    }
                    .font(.system(size: 9))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    Text("A Guide to the Coast's Best Hiking Trails").font(.system(size: 21, weight: .bold)).foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.top, 6)
                    Text("JULY 17, 2022").font(.system(size: 8, design: .monospaced)).foregroundStyle(.gray).padding(.horizontal, 16).padding(.top, 6)
                    ZStack(alignment: .topTrailing) {
                        photo
                        if !blocks { inlineAd.transition(.opacity) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer(minLength: 0)
                }
                .frame(width: 330)
                .background(Color.white)
                Toggle(isOn: $blocks.animation(.easeInOut(duration: 0.35))) {
                    Text(MobileOnboarding.blockingSwitch).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                }
                .tint(Color(.systemGreen))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 150)
                .accessibilityIdentifier("onboarding-blocking")
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var masthead: some View {
        VStack(spacing: 8) {
            Text("Trail & Tide").font(.system(size: 26, weight: .black, design: .serif)).foregroundStyle(.black).italic()
            HStack(spacing: 14) {
                Text("Things to Do"); Text("Eat & Drink"); Text("Happening this")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    /// Dusk over the hills, drawn: sky, then two ridges.
    private var photo: some View {
        LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.78), Color(red: 0.86, green: 0.7, blue: 0.68)], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    var far = Path()
                    far.move(to: CGPoint(x: 0, y: size.height * 0.62))
                    far.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.7), control: CGPoint(x: size.width * 0.35, y: size.height * 0.35))
                    far.addLine(to: CGPoint(x: size.width, y: size.height)); far.addLine(to: CGPoint(x: 0, y: size.height)); far.closeSubpath()
                    context.fill(far, with: .color(Color(red: 0.36, green: 0.35, blue: 0.45)))
                    var near = Path()
                    near.move(to: CGPoint(x: 0, y: size.height * 0.9))
                    near.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.78), control: CGPoint(x: size.width * 0.7, y: size.height * 0.55))
                    near.addLine(to: CGPoint(x: size.width, y: size.height)); near.addLine(to: CGPoint(x: 0, y: size.height)); near.closeSubpath()
                    context.fill(near, with: .color(Color(red: 0.22, green: 0.22, blue: 0.3)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var topAd: some View {
        VStack(spacing: 2) {
            Text("ADVERTISEMENT").font(.system(size: 7, weight: .medium)).foregroundStyle(.gray)
            HStack {
                Text("Loud Sound.").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(red: 0.5, green: 0.8, blue: 1)).fixedSize()
                Text("Tiny Speaker.\nUnreal Battery.").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(white: 0.08))
        }
        .accessibilityHidden(true)
    }

    private var inlineAd: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AD").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 4).background(Color.yellow)
            Text("Snack o'clock!\nTry the new crunch.").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(10)
        .frame(width: 170, height: 110, alignment: .topLeading)
        .background(LinearGradient(colors: [Color.orange, Color.red], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "xmark.square.fill").font(.system(size: 14)).foregroundStyle(.black, .white).padding(2)
        }
        .padding(.top, 70)
        .accessibilityHidden(true)
    }
}
