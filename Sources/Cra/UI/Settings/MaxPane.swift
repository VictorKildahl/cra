import AppKit
import SwiftUI

/// Arc's Max pane (Arc 1.171, Settings ▸ Max): one card, a row per feature with a picture in a
/// white frame, its name, what it does and a switch, and a line under the card about where the
/// data goes. Cra's features run on the Mac's own Apple Intelligence model, so that line says
/// nothing leaves the Mac, or, while Apple Intelligence can't run, why and how to turn it on.
struct MaxPane: View {
    @Environment(SidebarStore.self) private var store
    private var service: TidyTabsService { TidyTabsService.shared }

    var body: some View {
        @Bindable var store = store
        let available = service.status == .available
        SettingsCardPane {
            SettingsFeatureCard {
                SettingsSwitchRow("Tidy Tabs",
                                  detail: Text("Press the \(Image(nsImage: BroomGlyph.image).renderingMode(.template)) icon to let your Sidebar organize itself whenever you have six or more Today Tabs."),
                                  isOn: $store.settings.tidyTabs, enabled: available) {
                    TidyTabsPicture()
                }
                SettingsCardDivider()
                SettingsSwitchRow("Tidy Tab Titles",
                                  detail: "Have your tabs automatically renamed with tidier, shorter titles when you Pin them.",
                                  isOn: $store.settings.tidyTabTitles, enabled: available) {
                    TidyTabTitlesPicture()
                }
                SettingsCardDivider()
                SettingsSwitchRow("Tidy Downloads",
                                  detail: "Keep your many files more organized with smartly renamed downloads — and make them a little easier to find later.",
                                  isOn: $store.settings.tidyDownloads, enabled: available) {
                    TidyDownloadsPicture()
                }
            }
            MaxFooter(status: service.status) { service.openSystemSettings() }
                .padding(.top, 14)
        }
        // Coming back from System Settings brings Cra to the front, which reads the status again;
        // a model still downloading gets there without that.
        .task {
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Under the card, where Arc says Max sends data to its AI partners: what runs where, or why it
/// can't and the way to System Settings ▸ Apple Intelligence & Siri.
private struct MaxFooter: View {
    let status: TidyTabsService.Status
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text(status.explanation)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if status.canOpenSettings {
                Button(action: openSettings) {
                    Text("Turn on Apple Intelligence in System Settings").font(.system(size: 12)).underline()
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Arc's Tidy Downloads picture: the "Download renamed to:" card on blue.
private struct TidyDownloadsPicture: View {
    private let grey = Color(white: 0.55)
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.20, blue: 0.93)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("Download renamed to:").font(.system(size: 4)).foregroundStyle(grey).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                    Image(systemName: "xmark").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                }
                Text("Navan Itinerary.pdf").font(.system(size: 6, weight: .medium)).foregroundStyle(.black).lineLimit(1).fixedSize()
                Text("387494875.pdf").font(.system(size: 4.5)).strikethrough().foregroundStyle(grey).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(width: 70)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
        }
    }
}

/// Arc's Tidy Tab Titles picture: a renamed tab, "Double-click to rename" under it, sparkles round
/// it, on mauve.
private struct TidyTabTitlesPicture: View {
    private let ink = Color(red: 0.42, green: 0.27, blue: 0.62)
    var body: some View {
        ZStack {
            Color(red: 0.61, green: 0.48, blue: 0.62)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.32, green: 0.12, blue: 0.36))
                    .frame(width: 8, height: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Interior Design Book").font(.system(size: 6, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(1).fixedSize()
                    Text("Double-click to rename").font(.system(size: 4.5)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white))
            ForEach(0..<9, id: \.self) { i in
                Circle().fill(Color.white.opacity(i % 2 == 0 ? 0.9 : 0.6))
                    .frame(width: i % 3 == 0 ? 1.6 : 1.1, height: i % 3 == 0 ? 1.6 : 1.1)
                    .offset(x: [-33, -20, -6, 9, 22, 34, -26, 15, 30][i], y: [-12, 13, -14, 12, -13, 10, 9, -11, -6][i])
            }
        }
    }
}

/// Arc's Tidy Tabs picture: the squiggle, the broom and a ✕ on lavender.
private struct TidyTabsPicture: View {
    private let ink = Color(red: 0.55, green: 0.52, blue: 0.72)
    var body: some View {
        ZStack {
            Color(red: 0.84, green: 0.82, blue: 0.96)
            HStack(spacing: 5) {
                Squiggle()
                    .stroke(Color(red: 0.70, green: 0.67, blue: 0.90), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .frame(width: 40, height: 5)
                Image(nsImage: BroomGlyph.image).renderingMode(.template).foregroundStyle(ink)
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(ink)
            }
            .offset(x: -2)
        }
    }
}

private struct Squiggle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let period: CGFloat = 9
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        var x: CGFloat = 0
        while x <= r.width {
            p.addLine(to: CGPoint(x: r.minX + x, y: r.midY + r.height / 2 * sin(2 * .pi * x / period)))
            x += 0.5
        }
        return p
    }
}
