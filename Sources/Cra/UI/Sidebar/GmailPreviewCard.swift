import AppKit
import CraCEF
import SwiftUI

/// Arc's Previews card for a Gmail favorite (Arc 1.172.1, measured at 2x on Victor's Arc, 7 Nov 2026;
/// docs/screenshots/arc-gmail-preview-empty.png): 240 pt wide, #191817 with a 1 pt #3F3E3C edge and
/// 10 pt corners, its left edge 4 pt in from the tile's right edge and its top 3.5 pt above the tile's
/// bottom; the text centred, "No unread emails, you can exhale!" and a leaf when there is none.
@MainActor
final class GmailPreviewCard {
    static let shared = GmailPreviewCard()
    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private weak var tile: NSView?

    /// Hovering a Gmail tile: after a moment, its unread mail beside it.
    func hover(_ tile: NSView, favoriteURL: String, profilePath: String?) {
        guard let feed = GmailPreview.feedURL(for: favoriteURL) else { return }
        self.tile = tile
        pending?.cancel()
        let work = DispatchWorkItem { [weak self, weak tile] in
            CraCEFRuntime.fetchURL(feed, headers: nil, profilePath: profilePath) { status, _, _, body in
                MainActor.assumeIsolated {
                    guard let self, let tile, self.tile === tile, tile.window != nil else { return }
                    // Signed out: Gmail answers with its sign-in page, and Arc shows nothing.
                    guard status == 200, let inbox = GmailPreview.parse(body) else { return }
                    self.show(inbox, by: tile)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func leave(_ tile: NSView) {
        guard self.tile === tile else { return }
        pending?.cancel()
        pending = nil
        self.tile = nil
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        panel = nil
    }

    /// Testing without a Gmail sign-in (cra://debug?gmailPreview=<unread>): the card for a sample
    /// inbox, where it would hang under the fourth favorite tile of Arc's 264 pt sidebar.
    func demo(unread: Int, in window: NSWindow) {
        guard let content = window.contentView else { return }
        let anchor = NSView(frame: NSRect(x: 200, y: content.bounds.height - 44 - 47, width: 56, height: 47))
        content.addSubview(anchor)
        let mails = (0..<min(unread, 5)).map { GmailPreview.Mail(from: "Sender \($0 + 1)", subject: "Subject line \($0 + 1)") }
        show(GmailPreview.Inbox(unread: unread, mails: mails), by: anchor)
        anchor.removeFromSuperview()
    }

    private func show(_ inbox: GmailPreview.Inbox, by tile: NSView) {
        guard let window = tile.window else { return }
        panel?.orderOut(nil)
        let host = NSHostingView(rootView: GmailPreviewView(inbox: inbox))
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.contentView = host
        let t = window.convertToScreen(tile.convert(tile.bounds, to: nil))
        p.setFrameOrigin(NSPoint(x: t.maxX - 4, y: t.minY + 3.5 - size.height))
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
    }
}

private struct GmailPreviewView: View {
    let inbox: GmailPreview.Inbox

    var body: some View {
        VStack(alignment: inbox.mails.isEmpty ? .center : .leading, spacing: inbox.mails.isEmpty ? -2 : 8) {
            if inbox.mails.isEmpty {
                // Arc: the line centred 23.5 pt down, the leaf 38.5 pt, the card 62.5 pt tall.
                Text(GmailPreview.emptyText).font(.system(size: 13)).multilineTextAlignment(.center)
                Text("🍃").font(.system(size: 14))
            } else {
                Text(inbox.unread == 1 ? "1 unread email" : "\(inbox.unread) unread emails")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                ForEach(Array(inbox.mails.enumerated()), id: \.offset) { _, mail in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mail.from).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(mail.subject).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white.opacity(inbox.mails.isEmpty ? 0.78 : 0.88))
        .padding(.vertical, inbox.mails.isEmpty ? 15.5 : 12).padding(.horizontal, 16)
        .frame(width: 240, alignment: inbox.mails.isEmpty ? .center : .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 25 / 255, green: 24 / 255, blue: 23 / 255)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(red: 63 / 255, green: 62 / 255, blue: 60 / 255), lineWidth: 1))
    }
}
