import Foundation

/// The files one easel has in its folder: `<id>.json`, the `.bak` JSONStore keeps beside it, and its
/// pictures in `<id>/`. Library ▸ Easels ▸ Delete and sync remove an easel through it.
enum EaselFolder {
    static func remove(_ id: UUID, in folder: URL) {
        for name in [id.uuidString + ".json", id.uuidString + ".json.bak", id.uuidString] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
