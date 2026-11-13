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

extension EaselFiles {
    static var deleted: Set<UUID> = []
}
