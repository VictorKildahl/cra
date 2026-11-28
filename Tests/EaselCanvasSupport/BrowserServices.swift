import AppKit
import CraCEF

@MainActor
protocol NativePage: AnyObject {
    func owns(_ url: String) -> Bool
}

@MainActor
enum PageEngines {
    static var nativePage: ((NSRect, String, CraBrowserDelegate?, Bool, String?) -> CraBrowser?)?
    static var isNativePage: ((String) -> Bool)?
}

enum SettingsSync {
    static let easelsName = "Easels"
}

enum AppPaths {
    static let supportDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!)
}

final class JSONStore<T: Codable> {
    let url: URL
    init(_ name: String) { url = AppPaths.supportDir.appendingPathComponent(name) }
    func load(or fallback: () -> T) -> T {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback() }
        return value
    }
    func save(_ value: T) { saveNow(value) }
    func saveNow(_ value: T) { try! JSONEncoder().encode(value).write(to: url) }
}

enum EaselFolder {
    static func remove(_ id: UUID, in folder: URL) {
        for name in [id.uuidString + ".json", id.uuidString] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }
}

struct TabData { var url: String }
struct SidebarItem { var id = UUID(); var tab: TabData? }

@MainActor
final class SidebarStore {
    var tabs: [SidebarItem] = []
    func allTabs() -> [SidebarItem] { tabs }
}
