import AppKit

final class JSONStore<T: Codable> {
    let url = URL(fileURLWithPath: "/dev/null")
    func save(_ value: T) {}
    func saveNow(_ value: T) {}
}

@MainActor
enum EaselFiles {
    static var deleted: Set<UUID> = []
    static func store(_ id: UUID) -> JSONStore<Easel> { JSONStore() }
    static func pictures(_ id: UUID) -> URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
}
