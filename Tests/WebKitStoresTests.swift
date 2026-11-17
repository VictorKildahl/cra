import Foundation
import WebKit

/// WebKitStores in a process where nothing has touched WebKit yet, which is Cra at launch.
@main
enum WebKitStoresTests {
    @MainActor
    static func main() {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("cra-webkit-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: data) }
        setenv("CRA_DATA_DIR", data.path, 1)

        // ProfileCleanup runs before Chromium starts and drops a deleted profile's WebKit data.
        // WebKit's main run loop isn't set up until its first object, so its reply crashed Cra
        // at launch (three crash reports, 0.1.42 to 0.1.44, in WebsiteDataStore::removeDataStoreWithIdentifierImpl).
        var removed = false
        WebKitStores.removeProfile(folderName: "Profile 7") { removed = true }
        let deadline = Date().addingTimeInterval(10)
        while !removed, Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        guard removed else {
            print("FAIL: a deleted profile's WebKit data is removed before WebKit has started")
            exit(1)
        }
        print("WebKit stores: 1 check passed")
    }
}
