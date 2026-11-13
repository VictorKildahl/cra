import CraCore
import UIKit

/// Links saved through the share extension ("Saved" in other apps' share sheets) wait in the App
/// Group's inbox; the browser takes them whenever it comes to the front.
extension BrowserViewController {
    static var shareInboxFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MobileShareInbox.appGroup)
    }

    /// `-CraFakeShare <url>`: a test puts a link in the inbox as the extension would, in the real
    /// App Group, before the browser looks.
    static func saveFakeShareForTest() {
        guard let url = LaunchOptions.value("CraFakeShare"), let folder = shareInboxFolder else { return }
        let place = MobileShareInbox.Destination(rawValue: LaunchOptions.value("CraFakeShareTo") ?? "") ?? .tabs
        MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in
            inbox.save(url: url, title: "Shared page", to: place, at: Date())
        }
    }

    func takeSharedLinks() {
        guard let folder = Self.shareInboxFolder,
              let links = MobileShareInbox.update(in: folder, { (inbox: inout MobileShareInbox) in inbox.take() }), !links.isEmpty else { return }
        for link in links {
            switch link.destination {
            case .tabs: store.add(url: link.url, title: link.title)
            case .favorites: favorites.add(url: link.url, title: link.title)
            }
        }
        refreshTabStack()
        if isSearching, sheet.text.isEmpty {
            sheet.setFavorites(favorites.value.shown().map { ($0, favicons.icon(for: $0.url)) })
        }
    }
}
