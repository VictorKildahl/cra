import CraCore
import Foundation

/// `favorites.json` in the app's data folder (`MobileFavorites` in CraCore).
final class FavoritesStore {
    private let fileURL: URL
    private(set) var value: MobileFavorites

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("favorites.json")
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(MobileFavorites.self, from: data) {
            value = loaded
        } else {
            value = MobileFavorites()
        }
    }

    @discardableResult
    func toggle(url: String, title: String) -> Bool {
        let isFavorite = value.toggle(url: url, title: title)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: fileURL, options: .atomic) }
        return isFavorite
    }
}
