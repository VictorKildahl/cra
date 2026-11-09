import AppKit
import SwiftUI

/// Arc's UpdaterWindowController: a small window without a title that opens for Check for
/// Updates… Measured on Arc 1.170 in its up-to-date state (window capture and AX tree, 26 Oct):
/// 270 × 342, window background, the app icon 64 pt in an 84 pt frame at y 53, the name in
/// 24 pt bold (frame y 147, 30 tall), the version 11 pt (y 175) and the status line 13 pt
/// (y 209) in white 50%, and one 170 × 48 button at y 256, 38 above the bottom, radius 6
/// (continuous, fitted to the corner's anti-aliasing), filled with UpdaterButtonBackgroundColor
/// (white, black in dark mode), with a 13 pt bold label. The other states never showed on this
/// Mac and follow the same layout.
final class UpdaterWindowController: NSWindowController, NSWindowDelegate {
    private weak var updater: SoftwareUpdater?

    init(updater: SoftwareUpdater) {
        self.updater = updater
        let host = NSHostingController(rootView: UpdaterWindowView(updater: updater))
        host.sizingOptions = [.preferredContentSize]
        // Content runs under the transparent title bar, as in Arc.
        host.safeAreaRegions = []
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Software Update"
        w.isReleasedWhenClosed = false
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        super.init(window: w)
        w.delegate = self
        w.centerOnTestScreen()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { updater?.windowDidClose() }
    }
}

struct UpdaterWindowView: View {
    let updater: SoftwareUpdater

    private var current: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(10)
                .padding(.top, 53)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .frame(height: 30)
                .padding(.top, 10)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .updaterSecondary))
                .frame(height: 16)
                .padding(.top, -2)
            content
        }
        .frame(width: 270)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 38)
    }

    private var title: String {
        if case .found(let r, _) = updater.phase { return "Cra \(r.version)" }
        return "Cra"
    }

    private var subtitle: String {
        if case .found = updater.phase { return "You have \(current)" }
        return current
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .idle, .checking:
            status("Checking for updates…")
            UpdaterButton(title: "Cancel") { updater.dismissWindowAction() }
        case .upToDate:
            status("Your browser is up to date")
            UpdaterButton(title: "Close") { updater.dismissWindowAction() }
        case .found(let r, let downloaded):
            if let html = r.notesHTML, !html.isEmpty {
                ReleaseNotesView(html: html)
                    .padding(.top, 18)
            } else {
                status("A new version is available")
            }
            UpdaterButton(title: downloaded ? "Install and Relaunch" : "Download") { updater.installAndRelaunch() }
            LaterButton(title: "Later") { updater.dismissWindowAction() }
        case .downloading(let received, let expected):
            progress(expected > 0 ? Double(received) / Double(expected) : nil,
                     expected > 0 ? "\(Self.bytes(received)) of \(Self.bytes(expected))" : "Downloading…")
            UpdaterButton(title: "Cancel") { updater.dismissWindowAction() }
        case .extracting:
            progress(nil, "Preparing update…")
            UpdaterButton(title: "Install and Relaunch") {}.disabled(true)
        case .readyToInstall:
            status("Ready to Install")
            UpdaterButton(title: "Install and Relaunch") { updater.installAndRelaunch() }
        case .installing:
            progress(nil, "Installing update…")
            UpdaterButton(title: "Install and Relaunch") {}.disabled(true)
        case .failed(let message):
            status(message)
            UpdaterButton(title: "Download Manually") { updater.openDownloadPage() }
            LaterButton(title: "Close") { updater.dismissWindowAction() }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: .updaterSecondary))
            .multilineTextAlignment(.center)
            .frame(width: 208)
            .frame(minHeight: 18)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
            .padding(.bottom, 10)
    }

    private func progress(_ value: Double?, _ label: String) -> some View {
        VStack(spacing: 6) {
            if let value { ProgressView(value: value) } else { ProgressView().progressViewStyle(.linear) }
            Text(label).font(.system(size: 11)).foregroundStyle(Color(nsColor: .updaterSecondary)).monospacedDigit()
        }
        .controlSize(.small)
        .frame(width: 170)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private static func bytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

/// The wide button.
private struct UpdaterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(UpdaterButtonStyle())
            .accessibilityLabel(title)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 19)
    }
}

/// Arc's UpdaterButtonBackgroundColor with a faint shadow; the label is white ≈80% in dark mode.
private struct UpdaterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.primary.opacity(enabled ? 0.94 : 0.4))
            .frame(width: 170, height: 48)
            .background(shape.fill(Color(nsColor: .updaterButton)).shadow(color: .black.opacity(0.1), radius: 5))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Arc: "remind me to download and install the update later".
private struct LaterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Color(nsColor: .updaterSecondary))
            .keyboardShortcut(.cancelAction)
            .padding(.top, 12)
            .padding(.bottom, -12)
    }
}

/// Arc's ReleaseNotesView: the appcast item's HTML with Arc's style (-apple-system 12px,
/// list rows 20px, links #458AFF).
private struct ReleaseNotesView: View {
    let html: String

    var body: some View {
        ScrollView {
            Text(Self.render(html))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(width: 230, height: 150)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private static func render(_ html: String) -> AttributedString {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let styled = """
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont; font-size: 12px; color: \(dark ? "#fff" : "rgb(20, 20, 20)"); }
        li { line-height: 20px; }
        a, a:visited { color: #458AFF; }
        </style>
        """ + html
        guard let data = styled.data(using: .utf8),
              let s = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil),
              let a = try? AttributedString(s, including: \.appKit) else { return AttributedString(html) }
        return a
    }
}

private extension NSColor {
    /// The version and status lines: white 50% in dark mode (Arc measures 0.50, a touch under
    /// secondaryLabelColor's 0.55).
    static let updaterSecondary = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0, alpha: 0.5)
    }
    static let updaterButton = NSColor(name: "UpdaterButtonBackgroundColor") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    }
}
