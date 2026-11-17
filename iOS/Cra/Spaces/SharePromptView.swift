import CraCore
import SwiftUI
import UIKit

/// Arc Search 1.49 asks once, as the desktop's Spaces first arrive, to set up its share extension
/// (Victor's screenshot IMG_1898): the sync glow on white, a two-line title in Arc's blue, a grey
/// line under it, "Set up" and an outlined "No, thanks". Baselines are from the 440 pt screen,
/// relative to the sheet's middle.
struct SharePromptView: View {
    var setUp: () -> Void
    var noThanks: () -> Void

    static let blue = Color(red: 0x2F / 255, green: 0x39 / 255, blue: 0xFF / 255)
    private let grey = Color(white: 0x5E / 255)

    var body: some View {
        GeometryReader { geometry in
            let middle = geometry.size.height / 2
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                SyncGlow(background: .white)
                ForEach(Array(lines(MobileSyncIntro.shareTitle).enumerated()), id: \.offset) { index, line in
                    textLine(line, size: 31, weight: .heavy, color: Self.blue)
                        .position(x: width / 2, y: Self.center(baseline: middle - 136 + CGFloat(index) * 29.7, size: 31, weight: .heavy))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("share-prompt-title")
                ForEach(Array(lines(MobileSyncIntro.shareBody).enumerated()), id: \.offset) { index, line in
                    textLine(line, size: 18, weight: .regular, color: grey)
                        .position(x: width / 2, y: Self.center(baseline: middle - 63.6 + CGFloat(index) * 24.9, size: 18, weight: .regular))
                }
                .accessibilityElement(children: .combine)
                Button(action: setUp) {
                    Text(MobileSyncIntro.shareSetUp).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: width - 60, height: 58)
                        .background(Self.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .position(x: width / 2, y: middle + 36)
                .accessibilityIdentifier("share-prompt-set-up")
                Button(action: noThanks) {
                    Text(MobileSyncIntro.shareNoThanks).font(.system(size: 18, weight: .semibold)).foregroundStyle(Self.blue)
                        .frame(width: width - 60, height: 58)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Self.blue, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: width / 2, y: middle + 116)
                .accessibilityIdentifier("share-prompt-no-thanks")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .environment(\.colorScheme, .light)
    }

    /// Arc breaks the title after "Arc" and the line under it after "add": split the same way.
    private func lines(_ text: String) -> [String] {
        for marker in [" links from", " from other"] {
            if let range = text.range(of: marker) {
                return [String(text[..<range.lowerBound]), String(text[range.lowerBound...]).trimmingCharacters(in: .whitespaces)]
            }
        }
        return [text]
    }

    private func textLine(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Text(text).font(.system(size: size, weight: weight)).foregroundStyle(color).fixedSize()
    }

    /// Where to centre a one-line Text so its baseline lands at `baseline`.
    static func center(baseline: CGFloat, size: CGFloat, weight: Font.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight.uiKit)
        return baseline - font.ascender + font.lineHeight / 2
    }
}

extension Font.Weight {
    var uiKit: UIFont.Weight {
        switch self {
        case .heavy: .heavy
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        case .black: .black
        case .light: .light
        default: .regular
        }
    }
}

/// The how-to sheet behind "Set up" (IMG_1899): grey bold title and a plain close cross, three
/// steps with a blue label each and pictures of the share sheet under the second and third, a
/// chevron that says there is more, and "Show share menu" on white under a hairline. Positions are
/// Arc's on the 440 pt screen: the sheet's top is at 72, its fixed header 54 tall.
struct ShareGuideView: View {
    var close: () -> Void
    var showShareMenu: () -> Void

    private let grey = Color(white: 0x5E / 255)
    private static let header: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Text(MobileSyncIntro.guideTitle).font(.system(size: 19, weight: .bold)).foregroundStyle(grey).fixedSize()
                    .offset(x: 28, y: Self.top(baseline: 121.3 - 72, 19, .bold))
                    .accessibilityIdentifier("share-guide-title")
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(grey)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 440 - 400.5 - 22)
                .offset(y: 119 - 72 - 22)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("share-guide-close")
            }
            .frame(height: Self.header, alignment: .topLeading)
            .zIndex(1)
            ScrollView {
                // Content y = screen y - 126 (sheet top 72 + header 54).
                ZStack(alignment: .topLeading) {
                    step(MobileSyncIntro.guideSteps[0], baseline: 203.3 - 126)
                    step(MobileSyncIntro.guideSteps[1], baseline: 284.7 - 126)
                    ShareSheetPicture().offset(x: 34 - 32, y: 329 - 126)
                    step(MobileSyncIntro.guideSteps[2], baseline: 627.3 - 126)
                    AppsListPicture().offset(x: 34 - 32, y: 660 - 126)
                }
                .padding(.leading, 32)
                .frame(maxWidth: .infinity, minHeight: 660 - 126 + AppsListPicture.size.height + 30, alignment: .topLeading)
            }
            .scrollIndicatorsFlash(onAppear: true)
            .overlay(alignment: .bottom) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(grey)
                    .padding(.bottom, 831 - 798 - 4)
                    .accessibilityHidden(true)
            }
            Rectangle().fill(Color(white: 0xEF / 255)).frame(height: 1)
            Button(action: showShareMenu) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .medium))
                    Text(MobileSyncIntro.guideButton).font(.system(size: 19, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(SharePromptView.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.leading, 27)
            .padding(.trailing, 32)
            .padding(.top, 862 - 832)
            .accessibilityIdentifier("share-guide-show")
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// "Step N:" in blue bold, then the text in grey, an SF Symbol where the text says `{icon}`.
    /// A line break in the text starts a line 21.3 pt lower, as Arc's tight leading has it.
    private func step(_ step: MobileSyncIntro.GuideStep, baseline: CGFloat) -> some View {
        let lines = step.text.components(separatedBy: "\n")
        return ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                var text = index == 0
                    ? Text(step.label).font(.system(size: 19, weight: .bold)).foregroundColor(SharePromptView.blue) + Text("  ")
                    : Text("")
                let parts = line.components(separatedBy: "{icon}")
                for (at, part) in parts.enumerated() {
                    text = text + Text(part).font(.system(size: 19)).foregroundColor(grey)
                    if at < parts.count - 1, let symbol = step.symbol {
                        text = text + Text(Image(systemName: symbol)).font(.system(size: 18)).foregroundColor(symbol.hasSuffix(".fill") ? Color(white: 0.27) : grey)
                    }
                }
                return text.fixedSize().offset(y: Self.top(baseline: baseline + CGFloat(index) * 21.3, 19, .bold))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The top of a one-line Text whose baseline is at `baseline`.
    static func top(baseline: CGFloat, _ size: CGFloat, _ weight: Font.Weight = .regular) -> CGFloat {
        baseline - UIFont.systemFont(ofSize: size, weight: weight.uiKit).ascender
    }
}
