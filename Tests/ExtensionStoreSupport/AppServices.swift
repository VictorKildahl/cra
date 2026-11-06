import Foundation

enum AppPaths {
    static var supportDir: URL = {
        guard let path = ProcessInfo.processInfo.environment["CRA_DATA_DIR"] else {
            fatalError("Extension store tests require CRA_DATA_DIR")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var chromiumCache: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static func file(_ name: String) -> URL { supportDir.appendingPathComponent(name) }
}

struct ImportSource {
    let id: String
    var dataDir: URL { AppPaths.supportDir.appendingPathComponent("source-\(id)", isDirectory: true) }
    static let arc = ImportSource(id: "arc")
    static let dia = ImportSource(id: "dia")
    static let allCases: [ImportSource] = []
}

enum CraLog {
    static func note(_ message: String) {}
}
