import CraCore
import UIKit
import WebKit

/// The pictures of history items, for every tab's page swipe (`MobileHistoryPictures`). Held in
/// memory only, incognito tabs' too, so nothing of a page reaches the disk; all of them go on a
/// memory warning, since the swipe still works without its picture.
final class HistoryPictures {
    static let shared = HistoryPictures()

    /// The item is held weakly: its `ObjectIdentifier` alone could name a new item once the old
    /// one is freed, so an entry counts only while its item is still the same object.
    private struct Entry {
        weak var item: WKBackForwardListItem?
        let picture: UIImage
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var order = MobileRecentList<ObjectIdentifier>(limit: MobileHistoryPictures.kept)
    private var memoryWarning: NSObjectProtocol?

    private init() {
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                               object: nil, queue: .main) { [weak self] _ in self?.removeAll() }
    }

    func picture(for item: WKBackForwardListItem) -> UIImage? {
        let key = ObjectIdentifier(item)
        guard let entry = entries[key] else { return nil }
        guard entry.item === item else {
            forget(key)
            return nil
        }
        order.touch(key)
        return entry.picture
    }

    func keep(_ picture: UIImage, for item: WKBackForwardListItem) {
        // Items freed since (a closed tab, history cut off by a new navigation) make room first.
        for (key, entry) in entries where entry.item == nil { forget(key) }
        let key = ObjectIdentifier(item)
        entries[key] = Entry(item: item, picture: picture)
        for dropped in order.touch(key) { entries[dropped] = nil }
    }

    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    private func forget(_ key: ObjectIdentifier) {
        entries[key] = nil
        order.remove(key)
    }
}
